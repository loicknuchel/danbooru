# frozen_string_literal: true

class ModerationReport < ApplicationRecord
  MODEL_TYPES = %w[Dmail Comment ForumPost]

  attr_accessor :updater

  belongs_to :model, polymorphic: true
  belongs_to :creator, class_name: "User"

  validates :reason, presence: true
  validates :model_type, inclusion: { in: MODEL_TYPES }
  validates :creator, uniqueness: { scope: [:model_type, :model_id], message: "have already reported this message." }

  after_create :create_forum_post!
  after_create :autoban_reported_user
  after_save :notify_reporter
  after_save :create_modaction

  scope :dmail, -> { where(model_type: "Dmail") }
  scope :comment, -> { where(model_type: "Comment") }
  scope :forum_post, -> { where(model_type: "ForumPost") }
  scope :recent, -> { where("moderation_reports.created_at >= ?", 1.week.ago) }

  enum status: {
    pending: 0,
    rejected: 1,
    handled: 2,
  }

  def self.model_types
    MODEL_TYPES
  end

  def self.visible(user)
    if user.is_moderator?
      all
    else
      where(creator: user)
    end
  end

  def forum_topic_title
    "Reports requiring moderation"
  end

  def forum_topic_body
    "This topic deals with moderation events as reported by Builders. Reports can be filed against users, comments, or forum posts."
  end

  def forum_topic
    topic = ForumTopic.find_by_title(forum_topic_title)
    if topic.nil?
      CurrentUser.scoped(User.system) do
        topic = ForumTopic.create!(creator: User.system, title: forum_topic_title, category_id: 0, min_level: User::Levels::MODERATOR)
        ForumPost.create!(creator: User.system, body: forum_topic_body, topic: topic)
      end
    end
    topic
  end

  def forum_post_message
    <<~EOS
      [b]Report[/b] modreport ##{id}
      [b]Submitted by[/b] <@#{creator.name}>
      [b]Submitted against[/b] #{model.dtext_shortlink(key: true)} by <@#{reported_user.name}>
      [b]Reason[/b] #{reason}

      [quote]
      #{model.body}
      [/quote]
    EOS
  end

  def create_forum_post!
    updater = ForumUpdater.new(forum_topic)
    updater.update(forum_post_message)
  end

  def autoban_reported_user
    if SpamDetector.is_spammer?(reported_user)
      SpamDetector.ban_spammer!(reported_user)
    end
  end

  def notify_reporter
    return if creator == User.system
    return unless handled? && status_before_last_save != :handled

    Dmail.create_automated(to: creator, title: "Thank you for reporting #{model.dtext_shortlink}", body: <<~EOS)
      Thank you for reporting #{model.dtext_shortlink}. Action has been taken against the user.
    EOS
  end

  def create_modaction
    return unless saved_change_to_status? && status != :pending

    if handled?
      ModAction.log("handled modreport ##{id}", :moderation_report_handled, updater)
    elsif rejected?
      ModAction.log("rejected modreport ##{id}", :moderation_report_rejected, updater)
    end
  end

  def reported_user
    case model
    when Comment, ForumPost
      model.creator
    when Dmail
      model.from
    else
      raise NotImplementedError
    end
  end

  def self.search(params)
    q = search_attributes(params, :id, :created_at, :updated_at, :reason, :creator, :model, :status)
    q = q.text_attribute_matches(:reason, params[:reason_matches])

    q.apply_default_order(params)
  end

  def self.available_includes
    [:creator, :model]
  end
end
