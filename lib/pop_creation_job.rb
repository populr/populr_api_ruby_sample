
class PopCreationJobRow
  include Mongoid::Document
  field :columns, :type => Array, :default => []
  field :output, :type => Array, :default => nil
  field :pop_id, :type => String, :default => nil
  field :asset_id_to_column_index_map, :type => Hash, :default => {}

  embedded_in :job, :class_name => 'PopCreationJob'
end

class PopCreationJob < PopDeliveryConfiguration
  field :finished, :type => Boolean, :default => false
  field :started, :type => Boolean, :default => false
  field :failed_row_count, :type => Integer, :default => 0
  field :hash, :type => String
  field :email, :type => String

  embeds_many :rows, :class_name => 'PopCreationJobRow'

  def create_rows!(csv_lines)
    csv_lines.each do |line|
      row = self.rows.build
      row.columns = strip_whitespace(CSV.parse_line(line))
    end
    save!
  end

  def as_json(options = {})
    json = super(options)
    json[:created_at] = _id.generation_time
    json[:row_count] = rows.length
    json[:_id] = _id.to_s
    json[:hash] = self.hash
    json.delete('rows')
    json
  end

  def create_resque_tasks
    self.hash ||= (0...8).map{(65+rand(26)).chr}.join
    self.save!

    rows.each do |row|
      Resque.enqueue(PopCreationWorker, self._id, row._id)
    end
  end

end
