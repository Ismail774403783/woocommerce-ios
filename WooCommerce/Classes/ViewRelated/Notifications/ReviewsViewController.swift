import UIKit
import Gridicons
import Yosemite
import WordPressUI
import SafariServices
import Gridicons
import StoreKit


// MARK: - ReviewsViewController
//
final class ReviewsViewController: UIViewController {

    /// Main TableView.
    ///
    @IBOutlet private var tableView: UITableView!

    /// Mark all as read nav bar button
    ///
    private lazy var rightBarButton: UIBarButtonItem = {
        return UIBarButtonItem(image: .checkmarkImage,
                               style: .plain,
                               target: self,
                               action: #selector(markAllAsRead))
    }()

    private let viewModel = ReviewsViewModel(data: DefaultReviewsDataSource())

    /// Haptic Feedback!
    ///
    private let hapticGenerator = UINotificationFeedbackGenerator()

    /// Pull To Refresh Support.
    ///
    private lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(pullToRefresh(sender:)), for: .valueChanged)
        return refreshControl
    }()

    /// UI Active State
    ///
    private var state: State = .results {
        didSet {
            willEnter(state: state)

            guard oldValue != state else {
                return
            }
            didLeave(state: oldValue)
            didEnter(state: state)
        }
    }

    /// Indicates if there are no results onscreen.
    ///
    private var isEmpty: Bool {
        return viewModel.isEmpty
    }

    /// The last seen time for notifications
    ///
    private var lastSeenTime: String? {
        get {
            return UserDefaults.standard[.notificationsLastSeenTime]
        }
        set {
            return UserDefaults.standard[.notificationsLastSeenTime] = newValue
        }
    }

    /// The number of times the "Mark all as read" button was tapped
    ///
    private var markAsReadCount: Int {
        get {
            return UserDefaults.standard.integer(forKey: UserDefaults.Key.notificationsMarkAsReadCount.rawValue)
        }
        set {
            return UserDefaults.standard[.notificationsMarkAsReadCount] = newValue
        }
    }

    // MARK: - View Lifecycle

    deinit {
        stopListeningToNotifications()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        // This 👇 should be called in init so the tab is correctly localized when the app launches
        configureTabBarItem()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StyleManager.tableViewBackgroundColor

        refreshTitle()
        configureNavigationItem()
        configureNavigationBarButtons()
        configureTableView()
        configureTableViewCells()
        configureResultsController()

        startListeningToNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        resetApplicationBadge()
        transitionToResultsUpdatedState()
        synchronizeReviews()

        if AppRatingManager.shared.shouldPromptForAppReview(section: Constants.section) {
            displayRatingPrompt()
        }
    }

    func presentDetails(for noteId: Int) {
        viewModel.loadReview(for: noteId) { [weak self] in
            guard let self = self else {
                return
            }

            self.viewModel.delegate.presentReviewDetails(for: noteId, in: self)
        }
    }
}


// MARK: - User Interface Initialization
//
private extension ReviewsViewController {

    /// Setup: TabBar
    ///
    func configureTabBarItem() {
        tabBarItem.title = NSLocalizedString("Reviews", comment: "Title of the Reviews tab — plural form of Review")
        tabBarItem.image = .commentImage
    }

    /// Setup: Navigation
    ///
    func configureNavigationItem() {
        // Don't show the Settings title in the next-view's back button
        navigationItem.backBarButtonItem = UIBarButtonItem(title: String(), style: .plain, target: nil, action: nil)
    }

    /// Setup: NavigationBar Buttons
    ///
    func configureNavigationBarButtons() {
        rightBarButton.tintColor = .white
        rightBarButton.accessibilityTraits = .button
        rightBarButton.accessibilityLabel = NSLocalizedString("Mark All as Read", comment: "Accessibility label for the Mark All Reviews as Read Button")
        rightBarButton.accessibilityHint = NSLocalizedString("Marks Every Review as Read",
                                                            comment: "VoiceOver accessibility hint for the Mark All Reviews as Read Action")
        navigationItem.rightBarButtonItem = rightBarButton
    }

    /// Setup: TableView
    ///
    func configureTableView() {
        view.backgroundColor = StyleManager.tableViewBackgroundColor
        tableView.backgroundColor = StyleManager.tableViewBackgroundColor
        tableView.refreshControl = refreshControl
        tableView.dataSource = viewModel.dataSource

        // We decorate the delegate informally, because we want to intercept
        // didSelectItem:at: but delegate the rest of the implementation of
        // UITableViewDelegate to the implementation of UITableViewDelegate
        // provided by the view model. It could be argued that we are just cheating.
        tableView.delegate = self
    }

    /// Setup: ResultsController
    ///
    func configureResultsController() {
        viewModel.configureResultsController(tableView: tableView)
    }

    /// Setup: TableViewCells
    ///
    func configureTableViewCells() {
        viewModel.configureTableViewCells(tableView: tableView)
    }

    func refreshTitle() {
        transitionToResultsUpdatedState()
        navigationItem.title = NSLocalizedString(
            "Reviews",
            comment: "Title that appears on top of the main Reviews screen (plural form of the word Review)."
        )
    }
}


// MARK: - Actions
//
private extension ReviewsViewController {

    @IBAction func pullToRefresh(sender: UIRefreshControl) {
        ServiceLocator.analytics.track(.reviewsListPulledToRefresh)
        synchronizeReviews {
            sender.endRefreshing()
        }
    }

    @IBAction func markAllAsRead() {
        ServiceLocator.analytics.track(.reviewsListReadAllTapped)

        viewModel.markAllAsRead { [weak self] error in
            let tracks = ServiceLocator.analytics
            tracks.track(.reviewsMarkAllRead)

            guard let self = self else {
                return
            }

            if let error = error {
                DDLogError("⛔️ Error marking multiple notifications as read: \(error)")
                self.hapticGenerator.notificationOccurred(.error)

                tracks.track(.reviewsMarkAllReadFailed, withError: error)
            } else {
                self.hapticGenerator.notificationOccurred(.success)
                self.displayMarkAllAsReadNoticeIfNeeded()

                tracks.track(.reviewsMarkAllReadSuccess)
            }
            
            self.updateMarkAllReadButtonState()
            self.tableView.reloadData()
        }
    }
}


// MARK: - UITableViewDelegate
extension ReviewsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return viewModel.delegate.tableView?(tableView, heightForHeaderInSection: section) ?? 0
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return viewModel.delegate.tableView?(tableView, estimatedHeightForRowAt: indexPath) ?? 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return viewModel.delegate.tableView?(tableView, heightForRowAt: indexPath) ?? 0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.delegate.didSelectItem(at: indexPath, in: self)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        viewModel.delegate.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
    }
}

// MARK: - Yosemite Wrappers
//
private extension ReviewsViewController {

    /// Nukes the BadgeCount
    ///
    func resetApplicationBadge() {
        ServiceLocator.pushNotesManager.resetBadgeCount()
    }

    /// Synchronizes the Notifications associated to the active WordPress.com account.
    ///
    func synchronizeReviews(onCompletion: (() -> Void)? = nil) {
        transitionToSyncingState()
        viewModel.synchronizeReviews { [weak self] in
            self?.transitionToResultsUpdatedState()
            self?.tableView.reloadData()
            onCompletion?()
        }
    }
}


// MARK: - ResultsController
//
private extension ReviewsViewController {

    /// Refreshes the Results Controller Predicate, and ensures the UI is in Sync.
    ///
    func reloadResultsController() {
        tableView.setContentOffset(.zero, animated: false)
        tableView.reloadData()
        transitionToSyncingState()
    }
}


// MARK: - Placeholders
//
private extension ReviewsViewController {

    /// Renders Placeholder Reviews.
    ///
    func displayPlaceholderReviews() {
        viewModel.displayPlaceholderReviews(tableView: tableView)
    }

    /// Removes Placeholder Reviews.
    ///
    func removePlaceholderReviews() {
        viewModel.removePlaceholderReviews(tableView: tableView)
    }

    /// Displays the Empty State Overlay.
    ///
    func displayEmptyUnfilteredOverlay() {
        let overlayView: OverlayMessageView = OverlayMessageView.instantiateFromNib()
        overlayView.messageImage = .waitingForCustomersImage
        overlayView.messageText = NSLocalizedString("No Reviews Yet!", comment: "Empty Reviews List Message")
        overlayView.actionText = NSLocalizedString("Share your Store", comment: "Action: Opens the Store in a browser")
        overlayView.onAction = { [weak self] in
            guard let self = self else {
                return
            }
            guard let site = ServiceLocator.stores.sessionManager.defaultSite else {
                return
            }
            guard let url = URL(string: site.url) else {
                return
            }

            ServiceLocator.analytics.track(.reviewsShareStoreButtonTapped)
            SharingHelper.shareURL(url: url, title: site.name, from: overlayView.actionButtonView, in: self)
        }

        overlayView.attach(to: view)
    }

    /// Removes all of the the OverlayMessageView instances in the view hierarchy.
    ///
    func removeAllOverlays() {
        for subview in view.subviews where subview is OverlayMessageView {
            subview.removeFromSuperview()
        }
    }
}


// MARK: - Notifications
//
private extension ReviewsViewController {

    /// Setup: Notification Hooks
    ///
    func startListeningToNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(defaultSiteWasUpdated), name: .StoresManagerDidUpdateDefaultSite, object: nil)
        nc.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    /// Tear down the Notifications Hooks
    ///
    func stopListeningToNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    /// Default Site Updated Handler
    ///
    @objc func defaultSiteWasUpdated() {
        reloadResultsController()
    }

    /// Application became Active Again (while the Notes Tab was onscreen)
    ///
    @objc func applicationDidBecomeActive() {
        guard isViewLoaded == true && view.window != nil else {
            return
        }

        resetApplicationBadge()
    }
}


// MARK: - Finite State Machine Management
//
private extension ReviewsViewController {

    /// Runs prior to the FSM entering a new state.
    ///
    /// Note: Just because this func runs does not guarantee `didEnter()` or `didLeave()` will run as well.
    ///
    func willEnter(state: State) {
        updateNavBarButtonsState()
    }

    /// Runs whenever the FSM enters a State.
    ///
    func didEnter(state: State) {
        switch state {
        case .emptyUnfiltered:
            if isEmpty == true {
                displayEmptyUnfilteredOverlay()
            }
        case .results:
            break
        case .syncing:
            displayPlaceholderReviews()
        }
    }

    /// Runs whenever the FSM leaves a State.
    ///
    func didLeave(state: State) {
        switch state {
        case .emptyUnfiltered:
            removeAllOverlays()
        case .results:
            break
        case .syncing:
            removePlaceholderReviews()
        }
    }

    /// Should be called before Sync'ing Starts: Transitions to .results / .syncing
    ///
    func transitionToSyncingState() {
        state = isEmpty ? .syncing : .results
    }

    /// Should be called whenever the results are updated: after Sync'ing (or after applying a filter).
    /// Transitions to `.results` / `.emptyFiltered` / `.emptyUnfiltered` accordingly.
    ///
    func transitionToResultsUpdatedState() {
        if isEmpty == false {
            state = .results
            return
        }

        state = .emptyUnfiltered
    }
}


// MARK: - Private Helpers
//
private extension ReviewsViewController {

    /// Enables/disables the navbar buttons if needed
    ///
    /// - Parameter filterEnabled: If true, the filter navbar buttons is enabled; if false, it's disabled
    ///
    func updateNavBarButtonsState() {
        updateMarkAllReadButtonState()
    }

    func updateMarkAllReadButtonState() {
        rightBarButton.isEnabled = viewModel.hasUnreadNotifications
    }

    /// Displays the `Mark all as read` Notice if the number of times it was previously displayed is lower than the
    /// `Settings.markAllAsReadNoticeMaxViews` value.
    ///
    func displayMarkAllAsReadNoticeIfNeeded() {
        guard markAsReadCount < Settings.markAllAsReadNoticeMaxViews else {
            return
        }

        markAsReadCount += 1
        let message = NSLocalizedString("All reviews marked as read", comment: "Mark all reviews as read notice")
        let notice = Notice(title: message, feedbackType: .success)
        ServiceLocator.noticePresenter.enqueue(notice: notice)
    }
}


// MARK: - Nested Types
//
private extension ReviewsViewController {

    enum Settings {
        static let estimatedRowHeight             = CGFloat(88)
        static let placeholderRowsPerSection      = [3]
        static let markAllAsReadNoticeMaxViews    = 2
    }

    enum State {
        case emptyUnfiltered
        case results
        case syncing
    }

    struct Constants {
        static let section = "notifications"
    }
}
