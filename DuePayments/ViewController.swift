//
//  ViewController.swift
//  DuePayments
//
//  Created by Paweł Wojtkowiak on 31.03.2017.
//  Copyright © 2017 Paweł Wojtkowiak. All rights reserved.
//

import UIKit

class PaymentsTableViewController: UIViewController {
    private typealias `Self` = PaymentsTableViewController
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var addPaymentButton: UIBarButtonItem!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    var refreshControl: UIRefreshControl!
    
    var currentListId: String?
    var path: [String] = []
    var payment: Payment? {
        return PaymentProvider.shared.root.getPayment(atPath: path)
    }
    
    var customRowCount: Int {
        return 1
    }
    
    var rowCount: Int {
        return (payment?.payments.count ?? 0) + customRowCount
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView(frame: CGRect.zero)
        
        refreshControl = UIRefreshControl()
        refreshControl.attributedTitle = NSAttributedString(string: "PullToRefresh".localized)
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: UIControlEvents.valueChanged)
        tableView.addSubview(refreshControl)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        let doUpload = { [weak self] in
            self?.paymentsUpdated(upload: false)
        }
        
        if currentListId != AppSettings.shared.listId {
            fetchPayments() { status in
                if case .ok = status {
                    doUpload()
                }
            }
        } else {
            doUpload()
        }
    }
    
    func refresh(_ sender:AnyObject) {
        fetchPayments(showIndicator: false)
    }

    @IBAction func uploadPaymentsTapped(_ sender: UIBarButtonItem) {
        uploadPayments()
    }
}

extension PaymentsTableViewController {
    
    func showAddPayment() {
        let vc = AddPaymentViewController.instantiate(storyboard: "Main", identifier: "AddPaymentViewController")
        vc.path = path
        vc.actionType = .add
        vc.callback = { [weak self] payment, parentPath in
            guard let strongSelf = self else {
                return
            }
            
            guard let parentPayment = PaymentProvider.shared.root.getPayment(atPath: parentPath) else {
                print("This payment does not exist!")
                return
            }
            
            if parentPath.count > strongSelf.path.count && parentPayment.value > 0.0 {
                // value was not 0 - move to subpayments with the same name
                var newParentPayment = parentPayment
                newParentPayment.value = 0.0
                var oldParentPayment = parentPayment
                oldParentPayment.payments = []
                
                newParentPayment.payments.append(oldParentPayment)
                PaymentProvider.shared.root.replace(with: newParentPayment, atPath: parentPath)
            }
            PaymentProvider.shared.root.add(newPayment: payment, atPath: parentPath)
            strongSelf.paymentsUpdated()
            
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func deleteItem(at index: Int) {
        guard let name = payment?.payments[index].name else {
            return
        }
        
        var pathToRemove = path
        pathToRemove.append(name)
        let removedItem = PaymentProvider.shared.root.remove(atPath: pathToRemove)
        if removedItem == false {
            print("No items removed - path not found?")
            return
        }
        
        paymentsUpdated()
    }
    
    func editItem(at index: Int) {
        guard let payment = payment else {
            return
        }
        var oldPath = path
        oldPath.append(payment.payments[index].name)
        
        let vc = AddPaymentViewController.instantiate(storyboard: "Main", identifier: "AddPaymentViewController")
        vc.path = path
        vc.actionType = .edit
        vc.editedPayment = payment.payments[index]
        vc.callback = { [weak self] editedPayment, parentPath in
            
            guard let strongSelf = self else {
                return
            }
            
            if parentPath == strongSelf.path {
                PaymentProvider.shared.root.replace(with: editedPayment, atPath: oldPath)
            } else {
                PaymentProvider.shared.root.remove(atPath: oldPath)
                
                guard let parentPayment = PaymentProvider.shared.root.getPayment(atPath: parentPath) else {
                    print("This payment does not exist!")
                    return
                }
                
                if parentPath.count > strongSelf.path.count && parentPayment.value > 0.0 {
                    // value was not 0 - move to subpayments with the same name
                    var newParentPayment = parentPayment
                    newParentPayment.value = 0.0
                    var oldParentPayment = parentPayment
                    oldParentPayment.payments = []
                    
                    newParentPayment.payments.append(oldParentPayment)
                    PaymentProvider.shared.root.replace(with: newParentPayment, atPath: parentPath)
                }
                
                PaymentProvider.shared.root.add(newPayment: editedPayment, atPath: parentPath)
            }
            
            strongSelf.paymentsUpdated()
            
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func fetchPayments(showIndicator: Bool = true, completion: ((SyncStatus) -> ())? = nil) {
        if showIndicator {
            activityIndicator.startAnimating()
        }
        
        PaymentProvider.shared.download() { [weak self] status in
            
            self?.activityIndicator.stopAnimating()
            self?.refreshControl.endRefreshing()
            
            if let msg = status.errorMessage {
                let errorMsg = (msg != SyncStatus.genericError ? msg : "CouldNotDownloadPayments".localized)
                UIAlertController(errorMessage: errorMsg).present()
                completion?(status)
                return
            }
            
            self?.currentListId = AppSettings.shared.listId
            self?.paymentsUpdated(upload: false, completion: completion)
        }
    }
    
    func paymentsUpdated(upload: Bool = true, completion: ((SyncStatus) -> ())? = nil) {
        
        if path.isEmpty {
            title = "Payments".localized
        } else {
            title = payment?.name
        }
        
        tableView.reloadData()
        
        if upload && AppSettings.shared.generalSettings[.updateAfterEachChange] {
            uploadPayments(completion: completion)
        } else {
            completion?(.ok)
        }
    }
    
    func uploadPayments(completion: ((SyncStatus) -> ())? = nil) {
        startBlockingActivity()
        
        PaymentProvider.shared.upload() { [weak self] status in
            self?.stopBlockingActivity()
            
            if let msg = status.errorMessage {
                let errorMsg = (msg != SyncStatus.genericError ? msg : "CouldNotUploadPayments".localized)
                UIAlertController(errorMessage: errorMsg).present()
                completion?(status)
                return
            }
            
            if let payment = self?.payment,
                payment.payments.count == 0,
                let navigationController = self?.navigationController,
                navigationController.viewControllers.count > 1 {
                
                if let topVC = navigationController.viewControllers[navigationController.viewControllers.count - 1] as? PaymentsTableViewController {
                    topVC.paymentsUpdated(upload: false)
                }
                _ = navigationController.popViewController(animated: true)
            }
            
            completion?(.ok)
        }
    }
}

// MARK: IBActions

extension PaymentsTableViewController {
    @IBAction func addPayment(_ sender: UIBarButtonItem) {
        showAddPayment()
    }
}

// MARK: Table view

extension PaymentsTableViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rowCount
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = indexPath.row
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PaymentCell") as? PaymentCell else {
            fatalError("Reusable cell 'PaymentCell' not available")
        }
        
        guard row < rowCount else {
            fatalError("Trying to produce a cell for non existing payment")
        }
        
        if row < customRowCount {
            
            cell.nameLabel.textColor = UIColor.red
            cell.priceLabel.textColor = UIColor.red
            
            cell.nameLabel.text = "Total".localized
            cell.priceLabel.text = payment?.totalValue.toCurrencyString(localeIdentifier: "pl_PL") ?? "-"
            
            cell.accessoryType = .none
            cell.selectionStyle = .none
            cell.isUserInteractionEnabled = false
            
        } else {
            
            guard let payment = payment else {
                fatalError("This payment does not exist.")
            }
            
            let paymentIdx = row - customRowCount
            let currentPayment = payment.payments[paymentIdx]
            
            cell.nameLabel.text = currentPayment.name
            
            let totalValue = currentPayment.totalValue
            if totalValue != 0 {
                cell.priceLabel.text = totalValue.toCurrencyString(localeIdentifier: "pl_PL")
            } else {
                cell.priceLabel.text = ""
            }
            
            cell.accessoryType = currentPayment.payments.isEmpty ? .none : .disclosureIndicator
            cell.selectionStyle = currentPayment.payments.isEmpty ? .none : .default
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let row = indexPath.row
        
        guard row < rowCount else {
            return
        }

        if row < customRowCount {
            
        } else {
            let paymentIdx = row - customRowCount
            
            guard let payment = payment else {
                return
            }
            
            let currentPayment = payment.payments[paymentIdx]
            
            guard currentPayment.payments.count > 0 else {
                return
            }
            
            let vc = PaymentsTableViewController.instantiate(storyboard: "Main", identifier: "PaymentsTableViewController")
            vc.path = path
            vc.path.append(currentPayment.name)
            print(vc.path)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // TODO: Moving cells somehow
        return true
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        
        let paymentIdx = indexPath.row - customRowCount
        
        let deleteItem = UITableViewRowAction(style: .destructive, title: "Delete".localized) { [weak self] (action, indexPath) in
            self?.deleteItem(at: paymentIdx)
        }
        let editItem = UITableViewRowAction(style: .normal, title: "Edit".localized) { [weak self] (action, indexPath) in
            self?.editItem(at: paymentIdx)
        }
        return [deleteItem, editItem]
    }
}

