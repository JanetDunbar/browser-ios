/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SnapKit

private let ToolbarBaseAnimationDuration: CGFloat = 0.2

class BrowserScrollingController: NSObject {
    enum ScrollDirection {
        case up
        case down
    }

    enum ToolbarState {
        case collapsed
        case visible
        case animating
    }

    weak var browser: Browser? {
        willSet {
            self.scrollView?.delegate = nil
            self.scrollView?.removeGestureRecognizer(panGesture)
        }

        didSet {
            self.scrollView?.addGestureRecognizer(panGesture)
            scrollView?.delegate = self
        }
    }

    weak var header: UIView?
    weak var footer: UIView?
    weak var urlBar: URLBarView?
    weak var snackBars: UIView?

    var footerBottomConstraint: Constraint?
    var headerTopConstraint: Constraint?
    var toolbarsShowing: Bool { return headerTopOffset == 0 }

    fileprivate var headerTopOffset: CGFloat = 0 {
        didSet {
            headerTopConstraint?.update(offset: headerTopOffset)
            header?.superview?.setNeedsLayout()
        }
    }

    fileprivate var footerBottomOffset: CGFloat = 0 {
        didSet {
            footerBottomConstraint?.update(offset: footerBottomOffset)
            footer?.superview?.setNeedsLayout()
        }
    }

    fileprivate lazy var panGesture: UIPanGestureRecognizer = {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(BrowserScrollingController.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        return panGesture
    }()

    fileprivate var scrollView: UIScrollView? { return browser?.webView?.scrollView }
    fileprivate var contentOffset: CGPoint { return scrollView?.contentOffset ?? CGPoint.zero }
    fileprivate var contentSize: CGSize { return scrollView?.contentSize ?? CGSize.zero }
    fileprivate var scrollViewHeight: CGFloat { return scrollView?.frame.height ?? 0 }
    fileprivate var topScrollHeight: CGFloat { return header?.frame.height ?? 0 }
    fileprivate var bottomScrollHeight: CGFloat { return urlBar?.frame.height ?? 0 }
    fileprivate var snackBarsFrame: CGRect { return snackBars?.frame ?? CGRect.zero }

    fileprivate var lastContentOffset: CGFloat = 0
    fileprivate var scrollDirection: ScrollDirection = .down
    fileprivate var toolbarState: ToolbarState = .visible

    override init() {
        super.init()
    }

    func showToolbars(_ animated: Bool, completion: ((_ finished: Bool) -> Void)? = nil) {
        toolbarState = .visible
        let durationRatio = abs(headerTopOffset / topScrollHeight)
        let actualDuration = TimeInterval(ToolbarBaseAnimationDuration * durationRatio)
        self.animateToolbarsWithOffsets(
            animated,
            duration: actualDuration,
            headerOffset: 0,
            footerOffset: 0,
            alpha: 1,
            completion: completion)
    }

    func hideToolbars(_ animated: Bool, completion: ((_ finished: Bool) -> Void)? = nil) {
        toolbarState = .collapsed
        let durationRatio = abs((topScrollHeight + headerTopOffset) / topScrollHeight)
        let actualDuration = TimeInterval(ToolbarBaseAnimationDuration * durationRatio)
        self.animateToolbarsWithOffsets(
            animated,
            duration: actualDuration,
            headerOffset: -topScrollHeight,
            footerOffset: bottomScrollHeight,
            alpha: 0,
            completion: completion)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentSize" {
            if !checkScrollHeightIsLargeEnoughForScrolling() && !toolbarsShowing {
                showToolbars(true, completion: nil)
            }
        }
    }
}

private extension BrowserScrollingController {
    func browserIsLoading() -> Bool {
        return browser?.loading ?? true
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        if browserIsLoading() {
            return
        }

        if let containerView = scrollView?.superview {
            let translation = gesture.translation(in: containerView)
            let delta = lastContentOffset - translation.y

            if delta > 0 {
                scrollDirection = .down
            } else if delta < 0 {
                scrollDirection = .up
            }

            lastContentOffset = translation.y
            if checkRubberbandingForDelta(delta) && checkScrollHeightIsLargeEnoughForScrolling() {
                if toolbarState != .collapsed || contentOffset.y <= 0 {
                    scrollWithDelta(delta)
                }

                if headerTopOffset == -topScrollHeight {
                    toolbarState = .collapsed
                } else if headerTopOffset == 0 {
                    toolbarState = .visible
                } else {
                    toolbarState = .animating
                }
            }

            if gesture.state == .ended || gesture.state == .cancelled {
                lastContentOffset = 0
            }
        }
    }

    func checkRubberbandingForDelta(_ delta: CGFloat) -> Bool {
        return !((delta < 0 && contentOffset.y + scrollViewHeight > contentSize.height &&
                scrollViewHeight < contentSize.height) ||
                contentOffset.y < delta)
    }

    func scrollWithDelta(_ delta: CGFloat) {
        if scrollViewHeight >= contentSize.height {
            return
        }

        var updatedOffset = headerTopOffset - delta
        headerTopOffset = clamp(updatedOffset, min: -topScrollHeight, max: 0)
        if isHeaderDisplayedForGivenOffset(updatedOffset) {
            scrollView?.contentOffset = CGPoint(x: contentOffset.x, y: contentOffset.y - delta)
        }

        updatedOffset = footerBottomOffset + delta
        footerBottomOffset = clamp(updatedOffset, min: 0, max: bottomScrollHeight)

        let alpha = 1 - abs(headerTopOffset / topScrollHeight)
        urlBar?.updateAlphaForSubviews(alpha)
    }

    func isHeaderDisplayedForGivenOffset(_ offset: CGFloat) -> Bool {
        return offset > -topScrollHeight && offset < 0
    }

    func clamp(_ y: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if y >= max {
            return max
        } else if y <= min {
            return min
        }
        return y
    }

    func animateToolbarsWithOffsets(_ animated: Bool, duration: TimeInterval, headerOffset: CGFloat,
        footerOffset: CGFloat, alpha: CGFloat, completion: ((_ finished: Bool) -> Void)?) {

        let animation: () -> Void = {
            self.headerTopOffset = headerOffset
            self.footerBottomOffset = footerOffset
            self.urlBar?.updateAlphaForSubviews(alpha)
            self.header?.superview?.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: duration, animations: animation, completion: completion)
        } else {
            animation()
            completion?(true)
        }
    }

    func checkScrollHeightIsLargeEnoughForScrolling() -> Bool {
        return (UIScreen.main.bounds.size.height + 2 * UIConstants.ToolbarHeight) < scrollView?.contentSize.height ?? 0
    }
}

extension BrowserScrollingController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension BrowserScrollingController: UIScrollViewDelegate {
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if browserIsLoading() {
            return
        }

        if (decelerate || (toolbarState == .animating && !decelerate)) && checkScrollHeightIsLargeEnoughForScrolling() {
            if scrollDirection == .up {
                showToolbars(true)
            } else if scrollDirection == .down {
                hideToolbars(true)
            }
        }
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        showToolbars(true)
        return true
    }
}
