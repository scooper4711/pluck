import Foundation

/// Selecting by touch, where there is no ⌘-click: a tap adds to the selection or takes away from it.
extension PluckModel {
    /// Selects the page, or deselects it when it is selected.
    public func toggleSelection(ofPage pageIndex: Int) {
        selectedPages.formSymmetricDifference([pageIndex])
    }

    /// Selects the image, or deselects it when it is selected.
    public func toggleSelection(ofImage id: String) {
        selectedImageIDs.formSymmetricDifference([id])
    }

    /// Selects every image shown.
    public func selectAllVisibleImages() {
        selectedImageIDs = Set(visibleImages.map(\.id))
    }

    /// Makes the image the whole selection unless it is already part of it, so that a menu opened on an image
    /// that isn't selected acts on that image alone.
    public func selectForMenu(imageID id: String) {
        if !selectedImageIDs.contains(id) { selectedImageIDs = [id] }
    }
}
