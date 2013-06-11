
class PopCreationWorker
  attr_reader :job_id, :row_id
  @queue = :pop_task

  def self.perform(job_id, row_id)
    job = PopCreationJob.where(:id => job_id).first
    row = job.rows.where(:id => row_id).first
    return unless job && row

    unless job.started
      job.started = true
      job.save!
    end

    begin
      flush "Processing job with delivery config: #{job.delivery_config}"
      @populr = Populr.new(job.api_key, url_for_environment_named(job.api_env))
      @template = @populr.templates.find(job.template_id)

      data = {'file_regions' => {}, 'tags' => {}, 'embed_regions' => {}}
      data['slug'] = row.columns.first
      column_index = 1

      for tag in @template.api_tags
        data['tags'][tag] = row.columns[column_index]
        column_index += 1
      end
      for region, info in @template.api_regions
        if info['type'] == 'embed'
          data['embed_regions'][region] ||= []
          data['embed_regions'][region].push(row.columns[column_index])
        else
          data['file_regions'][region] ||= []
          data['file_regions'][region].concat(row.columns[column_index].split(','))
        end
        column_index += 1
      end
      user_email = row.columns[column_index]
      user_email = nil if user_email && user_email.empty?
      user_phone = row.columns[column_index+1]
      user_phone = nil if user_phone && user_phone.empty?

      flush "processing row: #{row.to_json}"

      create_and_send_pop(@template, data, job.delivery_config, user_email, user_phone) { |pop_reference, pop|
        flush "processed delivery #{user_email}, #{user_phone}"
        row.output = ['true', pop_reference, pop.password]
      }

    rescue Exception => e
      puts e.to_s
      row.output = ['false', "\"#{e.to_s}\"", '']

    ensure
      job.failed_row_count += 1 if row.output[0] == 'false'
      row.save!
      job.save!
      job.reload

      puts "Remaining rows: #{job.rows.where(:output.exists => false).count}"

      if job.rows.where(:output.exists => false).count == 0
        flush "Finished Job #{job._id}. Final email delivered to #{job.email}"
        job.finished = true
        job.save!

        send_notification(job.email, {
          :instructions => t.job.successful_with_errors(job.failed_row_count),
          :url => "#{ENV["DOMAIN"]}/job_results/#{job._id}/#{job.hash}",
          :password => nil
        })
      end
    end

  rescue Resque::TermException
    Resque.enqueue(self, job, row)
  end

  def self.flush(str)
    puts str
    $stdout.flush
  end

  def on_failure_retry(e, *args)
    puts "Performing #{self} caused an exception (#{e}). Retrying..."
    $stdout.flush
    Resque.enqueue self, *args
  end

end