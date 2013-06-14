
class PopCreationJobRow
  include Mongoid::Document
  field :columns, :default => []
  field :output, :default => nil

  embedded_in :job, :class_name => 'PopCreationJob'
end

class PopCreationJob < PopDeliveryConfiguration
  field :finished, :default => false
  field :started, :default => false
  field :failed_row_count, :default => 0
  field :hash
  field :email

  embeds_many :rows, :class_name => 'PopCreationJobRow'

  def create_rows!(csv_lines)
    csv_lines.each do |line|
      row = self.rows.build
      row.columns = strip_whitespace(CSV.parse_line(line))
    end
    save!
  end

  def create_resque_tasks
    self.hash ||= (0...8).map{(65+rand(26)).chr}.join
    self.save!

    rows.each do | row|
      Resque.enqueue(PopCreationWorker, self._id, row._id)
    end
  end

end
