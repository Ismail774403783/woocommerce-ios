import Yosemite

/// Implementation of `SearchUICommand` for Order search.
final class OrderSearchUICommand: SearchUICommand {
    typealias Model = Order
    typealias CellViewModel = OrderSearchCellViewModel
    typealias ResultsControllerModel = StorageOrder

    let searchBarPlaceholder = NSLocalizedString("Search all orders", comment: "Orders Search Placeholder")

    let emptyStateText = NSLocalizedString("No Orders found", comment: "Search Orders (Empty State)")

    private lazy var statusResultsController: ResultsController<StorageOrderStatus> = {
        let storageManager = ServiceLocator.storageManager
        let predicate = NSPredicate(format: "siteID == %lld", ServiceLocator.stores.sessionManager.defaultStoreID ?? Int.min)
        let descriptor = NSSortDescriptor(key: "slug", ascending: true)

        return ResultsController<StorageOrderStatus>(storageManager: storageManager, matching: predicate, sortedBy: [descriptor])
    }()

    init() {
        configureResultsController()
    }

    func createResultsController() -> ResultsController<ResultsControllerModel> {
        let storageManager = ServiceLocator.storageManager
        let descriptor = NSSortDescriptor(keyPath: \StorageOrder.dateCreated, ascending: false)
        return ResultsController<StorageOrder>(storageManager: storageManager, sortedBy: [descriptor])
    }

    func createCellViewModel(model: Order) -> OrderSearchCellViewModel {
        let orderDetailsViewModel = OrderDetailsViewModel(order: model)
        let orderStatus = lookUpOrderStatus(for: model)
        return OrderSearchCellViewModel(orderDetailsViewModel: orderDetailsViewModel,
                                        orderStatus: orderStatus)
    }

    /// Synchronizes the Orders matching a given Keyword
    ///
    func synchronizeModels(siteID: Int, keyword: String, pageNumber: Int, pageSize: Int, onCompletion: ((Bool) -> Void)?) {
        let action = OrderAction.searchOrders(siteID: siteID, keyword: keyword, pageNumber: pageNumber, pageSize: pageSize) { error in
            if let error = error {
                DDLogError("☠️ Order Search Failure! \(error)")
            }

            onCompletion?(error == nil)
        }

        ServiceLocator.stores.dispatch(action)
        ServiceLocator.analytics.track(.ordersListFilterOrSearch, withProperties: ["filter": "", "search": "\(keyword)"])
    }

    func didSelectSearchResult(model: Order, from viewController: UIViewController) {
        let identifier = OrderDetailsViewController.classNameWithoutNamespaces
        guard let detailsViewController = UIStoryboard.orders.instantiateViewController(withIdentifier: identifier) as? OrderDetailsViewController else {
            fatalError()
        }

        detailsViewController.viewModel = OrderDetailsViewModel(order: model)

        viewController.navigationController?.pushViewController(detailsViewController, animated: true)
    }
}

private extension OrderSearchUICommand {
    func configureResultsController() {
        try? statusResultsController.performFetch()
    }

    func lookUpOrderStatus(for order: Order) -> OrderStatus? {
        let listAll = statusResultsController.fetchedObjects
        for orderStatus in listAll where orderStatus.slug == order.statusKey {
            return orderStatus
        }

        return nil
    }
}
