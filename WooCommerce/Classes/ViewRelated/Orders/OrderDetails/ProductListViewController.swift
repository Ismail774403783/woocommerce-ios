import UIKit
import Yosemite

class ProductListViewController: UIViewController {
    @IBOutlet private var tableView: UITableView!

    var viewModel: OrderDetailsViewModel!
    private var items = [OrderItem]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.items = viewModel.order.items
        configureTableView()
        title = NSLocalizedString("Details Order #\(viewModel.order.number)", comment: "Screen title: Details Order number (number)")
    }

    func configureTableView() {
        tableView.estimatedSectionHeaderHeight = Constants.sectionHeight
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = Constants.rowHeight
        tableView.rowHeight = UITableViewAutomaticDimension

        let nib = ProductDetailsTableViewCell.loadNib()
        tableView.register(nib, forCellReuseIdentifier: ProductDetailsTableViewCell.reuseIdentifier)

        let headerNib = UINib(nibName: TwoColumnSectionHeaderView.reuseIdentifier, bundle: nil)
        tableView.register(headerNib, forHeaderFooterViewReuseIdentifier: TwoColumnSectionHeaderView.reuseIdentifier)
    }

    func itemAtIndexPath(_ indexPath: IndexPath) -> OrderItem {
        return items[indexPath.row]
    }
}

// MARK: - UITableViewDataSource Conformance
//
extension ProductListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = itemAtIndexPath(indexPath)
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ProductDetailsTableViewCell.reuseIdentifier, for: indexPath) as? ProductDetailsTableViewCell else {
            fatalError()
        }
        cell.configure(item: item, with: viewModel)
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let cell = tableView.dequeueReusableHeaderFooterView(withIdentifier: TwoColumnSectionHeaderView.reuseIdentifier) as? TwoColumnSectionHeaderView else {
            fatalError()
        }
        cell.configure(leftText: viewModel.productLeftTitle, rightText: viewModel.productRightTitle)

        return cell
    }
}

// MARK: - UITableViewDelegate Conformance
//
extension ProductListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Private methods and more
//
private extension ProductListViewController {
    struct Constants {
        static let sectionHeight = CGFloat(44)
        static let rowHeight = CGFloat(80)
    }
}