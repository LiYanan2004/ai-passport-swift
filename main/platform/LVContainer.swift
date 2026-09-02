final class LVContainer: LVObject {
    init?(parent: LVObject?) {
        super.init(lv_obj_create(parent?.opaquePointer))
    }
}
