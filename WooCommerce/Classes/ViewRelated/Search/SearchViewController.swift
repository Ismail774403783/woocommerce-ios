import Foundation
import UIKit
import Yosemite
import WordPressUI


/// SearchViewController: Displays the Search Interface for A Generic Model
///
final class SearchViewController<Cell: UITableViewCell & SearchResultCell, Command: SearchUICommand>:
    UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate
where Cell.SearchModel == Command.CellViewModel {

    /// Dismiss Action
    ///
    @IBOutlet private var cancelButton: UIButton!

    /// Empty State Legend
    ///
    @IBOutlet private var emptyStateLabel: UILabel!

    /// Main SearchBar
    ///
    @IBOutlet private var searchBar: UISearchBar!

    /// TableView
    ///
    @IBOutlet private var tableView: UITableView!

    /// Footer "Loading More" Spinner.
    ///
    private lazy var footerSpinnerView = {
        return FooterSpinnerView(tableViewStyle: tableView.style)
    }()

    /// ResultsController: Surrounds us. Binds the galaxy together. And also, keeps the UITableView <> (Stored) models in sync.
    ///
    private let resultsController: ResultsController<Command.ResultsControllerModel>

    /// SyncCoordinator: Keeps tracks of which pages have been refreshed, and encapsulates the "What should we sync now" logic.
    ///
    private let syncingCoordinator = SyncingCoordinator()

    /// Search Store ID
    ///
    private let storeID: Int

    /// Indicates if there are no results onscreen.
    ///
    private var isEmpty: Bool {
        return resultsController.isEmpty
    }

    /// Returns the active Keyword
    ///
    private var keyword: String {
        return searchBar.text ?? String()
    }

    /// UI Active State
    ///
    private var state: State = .results {
        didSet {
            didLeave(state: oldValue)
            didEnter(state: state)
        }
    }

    private let searchUICommand: Command


    /// Deinitializer
    ///
    deinit {
        stopListeningToNotifications()
    }

    /// Designated Initializer
    ///
    init(storeID: Int,
         command: Command,
         cellType: Cell.Type) {
        self.resultsController = command.createResultsController()
        self.searchUICommand = command
        self.storeID = storeID
        super.init(nibName: "SearchViewController", bundle: nil)
    }

    /// Unsupported: NSCoder
    ///
    required init?(coder aDecoder: NSCoder) {
        assertionFailure()
        return nil
    }


    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        registerTableViewCells()

        configureSyncingCoordinator()
        configureActions()
        configureEmptyStateLabel()
        configureMainView()
        configureSearchBar()
        configureTableView()
        configureResultsController()

        startListeningToNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: true)
        searchBar.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: true)
    }

    // MARK: - UITableViewDataSource Conformance
    //

    func numberOfSections(in tableView: UITableView) -> Int {
        return resultsController.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return resultsController.sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: Cell.reuseIdentifier, for: indexPath) as? Cell else {
            fatalError()
        }

        let model = resultsController.object(at: indexPath)
        let cellModel = searchUICommand.createCellViewModel(model: model)
        cell.configureCell(searchModel: cellModel)
        return cell
    }

    // MARK: - UITableViewDelegate Conformance
    //

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let model = resultsController.object(at: indexPath)
        searchUICommand.didSelectSearchResult(model: model, from: self)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let objectIndex = resultsController.objectIndex(from: indexPath)
        syncingCoordinator.ensureNextPageIsSynchronized(lastVisibleIndex: objectIndex)
    }

    // MARK: - UISearchBarDelegate Conformance
    //
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        synchronizeSearchResults(with: searchText)
    }

    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        return true
    }

    // MARK: - Notifications
    //

    /// Executed whenever `UIResponder.keyboardWillShowNotification` note is posted
    ///
    @objc func keyboardWillShow(_ note: Notification) {
        let bottomInset = keyboardHeight(from: note)

        tableView.contentInset.bottom = bottomInset
        tableView.scrollIndicatorInsets.bottom = bottomInset
    }

    /// Returns the Keyboard Height from a (hopefully) Keyboard Notification.
    ///
    func keyboardHeight(from note: Notification) -> CGFloat {
        let wrappedRect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        let keyboardRect = wrappedRect?.cgRectValue ?? .zero

        return keyboardRect.height
    }

    // MARK: - Actions
    //

    @IBAction func dismissWasPressed() {
        view.endEditing(true)
        dismiss(animated: true, completion: nil)
    }
}


// MARK: - User Interface Initialization
//
private extension SearchViewController {

    /// Setup: Main View
    ///
    func configureMainView() {
        view.backgroundColor = StyleManager.tableViewBackgroundColor
    }

    /// Setup: TableView
    ///
    func configureTableView() {
        tableView.backgroundColor = StyleManager.tableViewBackgroundColor
        tableView.estimatedRowHeight = Settings.estimatedRowHeight
        tableView.rowHeight = UITableView.automaticDimension
        tableView.tableFooterView = footerSpinnerView
    }

    /// Setup: Search Bar
    ///
    func configureSearchBar() {
        searchBar.placeholder = searchUICommand.searchBarPlaceholder
        searchBar.tintColor = .black
    }

    /// Setup: Actions
    ///
    func configureActions() {
        let title = NSLocalizedString("Cancel", comment: "")
        cancelButton.setTitle(title, for: .normal)
        cancelButton.titleLabel?.font = UIFont.body
    }

    /// Setup: No Results
    ///
    func configureEmptyStateLabel() {
        emptyStateLabel.text = searchUICommand.emptyStateText
        emptyStateLabel.textColor = StyleManager.wooGreyMid
        emptyStateLabel.font = .headline
        emptyStateLabel.adjustsFontForContentSizeCategory = true
        emptyStateLabel.numberOfLines = 0
    }

    /// Setup: Results Controller
    ///
    func configureResultsController() {
        resultsController.startForwardingEvents(to: tableView)
        try? resultsController.performFetch()
    }

    /// Setup: Sync'ing Coordinator
    ///
    func configureSyncingCoordinator() {
        syncingCoordinator.delegate = self
    }

    /// Registers all of the available TableViewCells
    ///
    func registerTableViewCells() {
        Cell.register(for: tableView)
    }

    /// Registers for all of the related Notifications
    ///
    func startListeningToNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    /// Unregisters from the Notification Center
    ///
    func stopListeningToNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
}


// MARK: - SyncingCoordinatorDelegate Conformance
//
extension SearchViewController: SyncingCoordinatorDelegate {

    /// Synchronizes the models for the Default Store (if any).
    ///
    func sync(pageNumber: Int, pageSize: Int, onCompletion: ((Bool) -> Void)? = nil) {
        let keyword = self.keyword
        searchUICommand.synchronizeModels(siteID: storeID,
                                          keyword: keyword,
                                          pageNumber: pageNumber,
                                          pageSize: pageSize,
                                        onCompletion: { [weak self] isCompleted in
                                            // Disregard OPs that don't really match the latest keyword
                                            if keyword == self?.keyword {
                                                self?.transitionToResultsUpdatedState()
                                            }
                                            onCompletion?(isCompleted)
        })
        transitionToSyncingState()
    }
}


// MARK: - Actions
//
private extension SearchViewController {

    /// Updates the Predicate + Triggers a Sync Event
    ///
    func synchronizeSearchResults(with keyword: String) {
        resultsController.predicate = NSPredicate(format: "ANY searchResults.keyword = %@", keyword)

        tableView.setContentOffset(.zero, animated: false)
        tableView.reloadData()

        syncingCoordinator.resynchronize()
    }
}


// MARK: - Spinner Helpers
//
extension SearchViewController {

    /// Starts the Footer Spinner animation, whenever `mustStartFooterSpinner` returns *true*.
    ///
    private func ensureFooterSpinnerIsStarted() {
        guard mustStartFooterSpinner() else {
            return
        }

        footerSpinnerView.startAnimating()
    }

    /// Whenever we're sync'ing a page of models that's beyond what we're currently displaying, this method will return *true*.
    ///
    private func mustStartFooterSpinner() -> Bool {
        guard let highestPageBeingSynced = syncingCoordinator.highestPageBeingSynced else {
            return false
        }

        return highestPageBeingSynced * SyncingCoordinator.Defaults.pageSize > resultsController.numberOfObjects
    }

    /// Stops animating the Footer Spinner.
    ///
    private func ensureFooterSpinnerIsStopped() {
        footerSpinnerView.stopAnimating()
    }
}


// MARK: - Placeholders
//
private extension SearchViewController {

    /// Displays the Empty State Legend.
    ///
    func displayEmptyState() {
        emptyStateLabel.isHidden = false
    }

    /// Removes the Empty State Legend.
    ///
    func removeEmptyState() {
        emptyStateLabel.isHidden = true
    }
}


// MARK: - FSM
//
private extension SearchViewController {

    func didEnter(state: State) {
        switch state {
        case .empty:
            displayEmptyState()
        case .syncing:
            ensureFooterSpinnerIsStarted()
        case .results:
            break
        }
    }

    func didLeave(state: State) {
        switch state {
        case .empty:
            removeEmptyState()
        case .syncing:
            ensureFooterSpinnerIsStopped()
        case .results:
            break
        }
    }

    /// Should be called before Sync'ing. Transitions to either `results` state.
    ///
    func transitionToSyncingState() {
        state = .syncing
    }

    /// Should be called whenever new results have been retrieved. Transitions to `.results` / `.empty` accordingly.
    ///
    func transitionToResultsUpdatedState() {
        state = isEmpty ? .empty : .results
    }
}


// MARK: - Private Settings
//
private enum Settings {
    static let estimatedHeaderHeight = CGFloat(43)
    static let estimatedRowHeight = CGFloat(86)
}


// MARK: - FSM States
//
private enum State {
    case syncing
    case results
    case empty
}
