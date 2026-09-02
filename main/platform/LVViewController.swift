class LVViewController {
    private(set) var view: LVObject?

    func viewDidLoad() {}
    func viewWillAppear() {}
    func viewDidAppear() {}
    func viewWillDisappear() {}
    func viewDidDisappear() {}

    func receiveButton(_ button: Int32, event: Int32) {
        _ = button
        _ = event
    }

    final func loadViewIfNeeded() {
        guard view == nil else {
            return
        }

        view = LVObject(lv_obj_create(nil))
        guard view != nil else {
            return
        }
        viewDidLoad()
    }

    final func presentView() {
        guard let view else {
            return
        }
        lv_screen_load(view.opaquePointer)
    }

    final func unloadView() {
        guard let view else {
            return
        }
        view.delete()
        self.view = nil
    }
}
