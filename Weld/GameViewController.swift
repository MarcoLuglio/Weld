//
//  GameViewController.swift
//  Weld
//
//  Created by Marco Luglio on 28/05/20.
//  Copyright © 2020 Marco Luglio. All rights reserved.
//

import Cocoa
import MetalKit



// Our macOS specific view controller
class GameViewController: NSViewController {

	//var mtkView: MTKView!
	var renderer: Renderer!

	override func viewDidLoad() {

		super.viewDidLoad()

		guard let mtkView = self.view as? MTKView else {
			print("View attached to GameViewController is not an MTKView")
			return
		}

		// Select the device to render with.  We choose the default device
		guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
			print("Metal is not supported on this device")
			return
		}

		mtkView.device = defaultDevice

		guard let newRenderer = Renderer(metalKitView: mtkView) else {
			print("Renderer cannot be initialized")
			return
		}

		self.renderer = newRenderer
		self.renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

		mtkView.delegate = renderer

	}

}
