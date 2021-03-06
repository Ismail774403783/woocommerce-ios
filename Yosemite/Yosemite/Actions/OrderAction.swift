import Foundation
import Networking



// MARK: - OrderAction: Defines all of the Actions supported by the OrderStore.
//
public enum OrderAction: Action {

    /// Searches orders that contain a given keyword.
    ///
    case searchOrders(siteID: Int, keyword: String, pageNumber: Int, pageSize: Int, onCompletion: (Error?) -> Void)

    /// Synchronizes the Orders matching the specified criteria.
    ///
    case synchronizeOrders(siteID: Int, statusKey: String?, pageNumber: Int, pageSize: Int, onCompletion: (Error?) -> Void)

    /// Nukes all of the cached orders.
    ///
    case resetStoredOrders(onCompletion: () -> Void)

    /// Retrieves the specified OrderID.
    ///
    case retrieveOrder(siteID: Int, orderID: Int, onCompletion: (Order?, Error?) -> Void)

    /// Updates a given Order's Status.
    ///
    case updateOrder(siteID: Int, orderID: Int, statusKey: String, onCompletion: (Error?) -> Void)

    /// Gets the number of orders in processing status.
    ///
    case countProcessingOrders(siteID: Int, onCompletion: (OrderCount?, Error?) -> Void)
}
