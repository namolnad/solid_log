module SolidLog
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
    connects_to database: { writing: :log, reading: :log }
  end
end
