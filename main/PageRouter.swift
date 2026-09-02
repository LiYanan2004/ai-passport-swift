final class LVPageRouter {
    private var activeViewController: LVViewController?

    var hasActiveViewController: Bool {
        activeViewController != nil
    }

    func show(_ viewController: LVViewController) {
        viewController.loadViewIfNeeded()
        guard viewController.view != nil else {
            return
        }

        let previousViewController = activeViewController
        previousViewController?.viewWillDisappear()
        viewController.viewWillAppear()
        viewController.presentView()

        activeViewController = viewController
        previousViewController?.viewDidDisappear()
        previousViewController?.unloadView()
        viewController.viewDidAppear()
    }

    func dismiss() {
        guard let activeViewController else {
            return
        }

        self.activeViewController = nil
        activeViewController.viewWillDisappear()
        activeViewController.viewDidDisappear()
        activeViewController.unloadView()
    }

    func dispatchButton(_ button: Int32, event: Int32) {
        activeViewController?.receiveButton(button, event: event)
    }
}
