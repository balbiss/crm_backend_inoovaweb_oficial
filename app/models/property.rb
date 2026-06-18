class Property < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true
  has_many_attached :photos

  after_create_commit :schedule_match_job

  def photo_urls
    return [] unless photos.attached?
    photos.map { |p| Rails.application.routes.url_helpers.rails_blob_url(p, host: ENV['API_HOST'] || 'http://localhost:3000') }
  end

  def photo_data
    return [] unless photos.attached?
    photos.map do |p|
      {
        id: p.id,
        url: Rails.application.routes.url_helpers.rails_blob_url(p, host: ENV['API_HOST'] || 'http://localhost:3000')
      }
    end
  end

  private

  def schedule_match_job
    PropertyMatchJob.perform_later(id)
  end
end
