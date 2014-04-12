class AppDelegate
  attr_accessor :status_menu

  CONFIG = YAML::load(NSMutableData.dataWithContentsOfURL(
    NSBundle.mainBundle.URLForResource("config", withExtension: "yml")).to_s)

  def applicationDidFinishLaunching(notification)
    @app_name = NSBundle.mainBundle.infoDictionary['CFBundleDisplayName']

    @window = PopupPanel.alloc.initPopup

    @status_menu = NSMenu.new
    @status_menu.delegate = self

    @status_item = NSStatusBar.systemStatusBar.statusItemWithLength(NSVariableStatusItemLength).init
    @status_item.setHighlightMode(true)
    @status_item.setTitle(@app_name)

    @status_item.setTarget(self)
    @status_item.setAction('showHide:')

    @http_state = createMenuItem("Loading...", '')
    @status_menu.addItem NSMenuItem.separatorItem
    @http_state.enabled = false
    @status_menu.addItem @http_state

    @status_menu.addItem NSMenuItem.separatorItem
    @status_menu.addItem createMenuItem("About #{@app_name}", 'orderFrontStandardAboutPanel:')
    @status_menu.addItem createMenuItem("Quit", 'terminate:')

    @unseen = 0
    @github = GitHub.new(CONFIG[:github_token]) do
      self.checkForNewEvents
    end

    NSUserNotificationCenter.defaultUserNotificationCenter.setDelegate(self)
  end

  def createMenuItem(name, action)
    NSMenuItem.alloc.initWithTitle(name, action: action, keyEquivalent: '')
  end

  def checkForNewEvents
    begin
      @http_state.title = "Working..."
      @github.events do |events|
        @http_state.title = "Processing..."

        unless events.empty?
          @events.each { |item| @status_menu.removeItem(item) } unless @events.nil?
          @events = []
          @urls = {}
          @last_commits = @commits || []
          @commits = []

          counter = 0
          events.reverse.each do |event|
            next unless event["type"] == "PushEvent"
            next if event["payload"].nil? || event["payload"]["commits"].nil?

            commits = event["payload"]["commits"].select{ |c| c["distinct"] }

            next if commits.length == 0

            actor = event['actor']['login']
            repo = event['repo']['name']

            commits.each do |commit|
              message = commit['message'].split("\n").first
              message = "#{message[0...30]}..." if message.length > 35
              @urls[counter] = commit['url'].gsub("api.", "").gsub("/repos", "").gsub("/commits", "/commit")
              item = self.createMenuItem("[#{actor}: #{repo} - #{message}", "pressEvent:")
              item.tag = counter
              @events << item
              @status_menu.insertItem(item, atIndex: 0)
              counter += 1
              @commits << commit['sha']
            end
          end

          new_commits = (@commits - @last_commits).length
          @unseen += new_commits
          self.showUnseenCommits
          self.showNotification(new_commits)
        end

        @http_state.title = "Ready"
      end
    rescue
      @http_state.title = "Error, retrying again shortly"
    ensure
      NSTimer.scheduledTimerWithTimeInterval(CONFIG[:timer],
        target: self,
        selector: 'checkForNewEvents',
        userInfo: nil,
        repeats: false)
    end
  end

  def showUnseenCommits
    @status_item.setTitle("#{@unseen.zero? ? 'No' : @unseen} new #{@unseen == 1 ? 'commit' : 'commits'}")
  end

  def menuWillOpen(menu)
    @unseen = 0
    self.showUnseenCommits
  end

  def pressEvent(item)
    NSWorkspace.sharedWorkspace.openURL(NSURL.URLWithString(@urls[item.tag]))
  end

  def showNotification(new_commits)
    return unless new_commits > 0
    notification = NSUserNotification.alloc.init
    notification.title = "New commits"
    notification.informativeText = "There are #{new_commits} new commits."
    notification.soundName = NSUserNotificationDefaultSoundName
    NSUserNotificationCenter.defaultUserNotificationCenter.scheduleNotification(notification)
  end

  def userNotificationCenter(center, didActivateNotification: notification)
    @status_item.popUpStatusItemMenu(@status_menu)
    center.removeDeliveredNotification(notification)
  end

  def showHide(sender)
    @unseen = 0
    self.showUnseenCommits
    @window.showHide(sender)
  end
end