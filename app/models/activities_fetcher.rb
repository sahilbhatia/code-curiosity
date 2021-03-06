class ActivitiesFetcher
  TRACKING_EVENTS = {'IssueCommentEvent' => 'comment', 'IssuesEvent' => 'issue'}

  attr_accessor :user, :round

  def initialize(user, round)
    @user = user
    @round = round
  end

  def fetch(type = :daily)
    since_time = if type == :daily
                   Time.now - 30.hours
                 else
                   round.from_date.beginning_of_day
                 end

    end_time = round.end_date.try(:end_of_day) || Date.today.end_of_day
    #repos = user.repositories.inject({}){|o, r| o[r.gh_id] = r; o}
    activities = user.gh_client.activity.events.performed(user.github_handle, auto_pagination: true)
    
    activities.each do |a|
      if TRACKING_EVENTS.key?(a.type) && (Time.parse(a.created_at)).between?(since_time, end_time)
        repo = Repository.where(gh_id: a.repo.id).first
        repo = self.create_repo(a.repo.id) unless repo
        create_activity(a, repo) if repo && !repo.ignore
      end
    end
  end

  def create_activity(activity, repo)
    type = TRACKING_EVENTS[activity.type]

    return unless user.github_handle == activity.payload[type].user.login

    user_activity = user.activities.find_or_initialize_by(gh_id: activity.id)
    user_activity.event_type = type
    user_activity.event_action = activity.payload['action']
    user_activity.description = activity.payload[type].body
    user_activity.repo = activity.repo.name
    user_activity.ref_url = activity.payload[type].html_url
    user_activity.commented_on = Time.parse(activity.created_at)
    user_activity.user = user
    user_activity.repository = repo
    user_activity.organization_id = repo.organization_id
    user_activity.round = round
    user_activity.save
  end

  def create_repo(repo_id)
    info = user.gh_client.repos.get_by_id(repo_id)

    if info.stargazers_count >= REPOSITORY_CONFIG['popular']['stars']
      repo = Repository.build_from_gh_info(info)
      repo.save

      return repo
    end
  end
end
