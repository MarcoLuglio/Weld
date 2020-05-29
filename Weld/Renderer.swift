//
//  Renderer.swift
//  Weld
//
//  Created by Marco Luglio on 28/05/20.
//  Copyright © 2020 Marco Luglio. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

import GameController // xbox and ps bluetooth controllers support



let maxBuffersInFlight = 3

enum RendererError: Error {
	case badVertexDescriptor
}

struct Uniforms {
	var modelViewMatrix: float4x4
	var projectionMatrix: float4x4
}

class Renderer: NSObject, MTKViewDelegate {

	public let device: MTLDevice
	let commandQueue: MTLCommandQueue
	var mdlVertexDescriptor: MDLVertexDescriptor
	var mtlVertexDescriptor: MTLVertexDescriptor
	var pipelineState: MTLRenderPipelineState
	var depthState: MTLDepthStencilState

	let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

	var projectionMatrix: simd_float4x4 = simd_float4x4()

	var playerMovementX: Float = 0
	var playerMovementY: Float = 0
	let playerMovementZ: Float = 0

	var playerRotationX: Float = 0
	var playerRotationY: Float = 0
	var playerRotationZ: Float = 0

	var playerTranslationX: Float = 0
	var playerTranslationY: Float = 0
	let playerTranslationZ: Float = 0


	/// Pitch
	var cameraRotationX: Float = 0

	/// Yaw
	var cameraRotationY: Float = 0

	/// Roll
	var cameraRotationZ:Float = 0

	/// Camera translation for peeking around
	var cameraTranslationX:Float = 0

	/// Camera translation for peeking around
	var cameraTranslationY:Float = 0

	/// Also know as truck, moves the camera back and forth, but it is not a true zoom because we are not changing the the lenses (perspective matrix)
	var cameraDolly:Float = -1.0

	var metalModels:[MetalModel]

	init?(metalKitView: MTKView) {

		self.device = metalKitView.device!
		self.commandQueue = self.device.makeCommandQueue()!
		self.mdlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
		self.mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(self.mdlVertexDescriptor)!

		metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
		metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
		metalKitView.sampleCount = 1

		do {
			self.pipelineState = try Renderer.buildRenderPipelineWithDevice(
				device: self.device,
				mtkView: metalKitView,
				mtlVertexDescriptor: mtlVertexDescriptor
			)
		} catch {
			print("Unable to compile render pipeline state.  Error info: \(error)")
			return nil
		}

		self.metalModels = [MetalModel]()
		self.metalModels.append(MetalModel(resource:"teapot", mdlVertexDescriptor:mdlVertexDescriptor, debugGroup:"teapot debug group", device:device))

		let depthStateDescriptor = MTLDepthStencilDescriptor()
		depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
		depthStateDescriptor.isDepthWriteEnabled = true
		self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!

		super.init()

		// TODO fix barulhos de atalhos do teclado. Talvez a view sendo first responder resolva... Mas aí talvez tenha que fazer uma subclass
		NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown, handler: self.keyDownHandler(event:))
		NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyUp, handler: self.keyUpHandler(event:))

	}

	class func buildMetalVertexDescriptor() -> MDLVertexDescriptor {

		// for each pipeline state object there can only be on vertex descriptor

		let vertexDescriptor = MDLVertexDescriptor() // model io
		vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,			format: .float3, offset: 0,								bufferIndex: 0)
		vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,				format: .float3, offset: MemoryLayout<Float>.size * 3,	bufferIndex: 0)
		vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,	format: .float2, offset: MemoryLayout<Float>.size * 6,	bufferIndex: 0)
		vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)

		return vertexDescriptor

	}

	class func buildRenderPipelineWithDevice(
		device: MTLDevice,
		mtkView: MTKView,
		mtlVertexDescriptor: MTLVertexDescriptor
	) throws -> MTLRenderPipelineState {

		let library = device.makeDefaultLibrary()

		let vertexFunction = library?.makeFunction(name: "vertex_main")
		let fragmentFunction = library?.makeFunction(name: "fragment_main")

		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.label = "RenderPipeline"
		pipelineDescriptor.sampleCount = mtkView.sampleCount
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor

		pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
		pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
		pipelineDescriptor.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat

		return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

	}

	private func updateGameState() {

		ObserveForGameControllers()

		for metalModel in self.metalModels {

			// For debug only
			self.playerTranslationX += self.playerMovementX / 100
			self.playerTranslationY += self.playerMovementY / 100
			metalModel.translationX = self.playerTranslationX
			metalModel.translationY = self.playerTranslationY
			metalModel.translationZ = self.cameraDolly

			//metalModel.rotationY = self.cameraRotationY
			metalModel.rotationY = self.playerRotationY * 60

			metalModel.update()

		}

	}

	func draw(in view: MTKView) {
		/// Per frame updates hare

		_ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

		guard let commandBuffer = commandQueue.makeCommandBuffer() else {
			return
		}

		let semaphore = inFlightSemaphore
		commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
			semaphore.signal()
		}

		self.updateGameState()

		let renderPassDescriptor = view.currentRenderPassDescriptor
		let drawable = view.currentDrawable

		if renderPassDescriptor == nil || drawable == nil {
			return
		}

		let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)!
		renderCommandEncoder.setCullMode(.back)
		renderCommandEncoder.setFrontFacing(.counterClockwise)
		renderCommandEncoder.setRenderPipelineState(self.pipelineState)
		renderCommandEncoder.setDepthStencilState(self.depthState)

		for metalModel in self.metalModels {
			metalModel.draw(renderCommandEncoder, projectionMatrix: self.projectionMatrix)
		}

		renderCommandEncoder.endEncoding() // no more drawing after here

		if let drawable = view.currentDrawable {
			commandBuffer.present(drawable)
		}

		commandBuffer.commit()

	}

	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		let aspect = Float(size.width) / Float(size.height)
		projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
	}

	// MARK: - Keyboard

	func keyDownHandler(event: NSEvent) -> NSEvent? {

		//print(event)

		switch event.keyCode {

			case 13: // w
				self.cameraDolly += 0.05

			case 1: // s
				self.cameraDolly -= 0.05

			case 0: // a
				self.cameraRotationY += 0.1

			case 2: // d
				self.cameraRotationY -= 0.1

			case 126: // arrow up
				self.cameraTranslationY += 0.05

			case 125: // arrow down
				self.cameraTranslationY -= 0.05

			case 123: // arrow left
				self.cameraTranslationX -= 0.05

			case 124: // arrow right
				self.cameraTranslationX += 0.05

			default:
				break

		}

		return event

	}

	func keyUpHandler(event: NSEvent) -> NSEvent? {

		//print(event)
		return event

	}

	// MARK: - Game controllers

	private func ObserveForGameControllers() {

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(connectControllers),
			name: NSNotification.Name.GCControllerDidConnect,
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(disconnectControllers),
			name: NSNotification.Name.GCControllerDidDisconnect,
			object: nil
		)

	}

	@objc func connectControllers() {
		// Unpause the Game if it is currently paused
		//self.isPaused = false

		// Used to register the Nimbus Controllers to a specific Player Number
		var indexNumber = 0

		// Run through each controller currently connected to the system
		for controller in GCController.controllers() {

			if controller.extendedGamepad != nil {
				controller.playerIndex = GCControllerPlayerIndex.init(rawValue: indexNumber)!
				indexNumber += 1
				setupControllerControls(controller: controller)
			} else if controller.microGamepad != nil {
				// TODO
			}

		}

	}

	@objc func disconnectControllers() {
		// Pause the Game if a controller is disconnected ~ This is mandated by Apple
		// self.isPaused = true
	}

	func setupControllerControls(controller:GCController) {

		controller.extendedGamepad?.valueChangedHandler = {(gamepad: GCExtendedGamepad, element: GCControllerElement) in
			// Add movement in here for sprites of the controllers
			self.controllerInputDetected(gamepad: gamepad, element: element, index: controller.playerIndex.rawValue)
		}

		// AppleTV controller only...
		controller.motion?.valueChangedHandler = {(motion:GCMotion) in
			self.controllerMotionDetected(motion: motion, index: controller.playerIndex.rawValue)
		}

	}

	func controllerInputDetected(gamepad:GCExtendedGamepad, element:GCControllerElement, index:Int) {

		switch element {

			// MARK: - Player movement
			case gamepad.leftThumbstick:

				playerMovementX = gamepad.leftThumbstick.xAxis.value + gamepad.dpad.xAxis.value
				if playerMovementX > 1 {
					playerMovementX = 1
				} else if playerMovementX < -1 {
					playerMovementX = -1
				}

				if (gamepad.leftThumbstick.xAxis.value != 0) {
					print("Controller: \(index), LeftThumbstickXAxis: \(gamepad.leftThumbstick.xAxis.value)")
				}

				playerMovementY = gamepad.leftThumbstick.yAxis.value + gamepad.dpad.yAxis.value
				if playerMovementY > 1 {
					playerMovementY = 1
				} else if playerMovementY < -1 {
					playerMovementY = -1
				}

				if (gamepad.leftThumbstick.yAxis.value != 0) {
					print("Controller: \(index), LeftThumbstickYAxis: \(gamepad.leftThumbstick.yAxis.value)")
				}

			case gamepad.dpad:

				playerMovementX = gamepad.leftThumbstick.xAxis.value + gamepad.dpad.xAxis.value
				if playerMovementX > 1 {
					playerMovementX = 1
				} else if playerMovementX < -1 {
					playerMovementX = -1
				}

				if (gamepad.dpad.xAxis.value != 0) {
					print("Controller: \(index), D-PadXAxis: \(gamepad.dpad.xAxis.value)")
				}

				playerMovementY = gamepad.leftThumbstick.yAxis.value + gamepad.dpad.yAxis.value
				if playerMovementY > 1 {
					playerMovementY = 1
				} else if playerMovementY < -1 {
					playerMovementY = -1
				}

				if (gamepad.dpad.yAxis.value != 0) {
					print("Controller: \(index), D-PadYAxis: \(gamepad.dpad.yAxis.value)")
				}

			// MARK: - Camera movement
			case gamepad.rightThumbstick:

				cameraTranslationX = gamepad.rightThumbstick.xAxis.value * 10
				if (gamepad.rightThumbstick.xAxis.value != 0) {
					print("Controller: \(index), rightThumbstickXAxis: \(gamepad.rightThumbstick.xAxis.value)")
				}

				cameraTranslationY = gamepad.rightThumbstick.yAxis.value * 10
				if (gamepad.rightThumbstick.yAxis.value != 0) {
					print("Controller: \(index), rightThumbstickYAxis: \(gamepad.rightThumbstick.yAxis.value)")
				}

			case gamepad.buttonA: // ✕?
				print("Controller: \(index), A: \(gamepad.buttonA.value)")
			// TODO jump

			case gamepad.buttonB: // ○?
				print("Controller: \(index), B: \(gamepad.buttonB.value)")

			case gamepad.buttonX: // □?
				print("Controller: \(index), X: \(gamepad.buttonX.value)")

			case gamepad.buttonY: // △?
				print("Controller: \(index), Y: \(gamepad.buttonY.value)")

			case gamepad.leftShoulder:
				print("Controller: \(index), left shoulder: \(gamepad.leftShoulder.value)")

			case gamepad.rightShoulder:
				print("Controller: \(index), right shoulder: \(gamepad.rightShoulder.value)")

			case gamepad.leftTrigger:
				playerRotationY = gamepad.rightTrigger.value - gamepad.leftTrigger.value
				print("Controller: \(index), left trigger: \(gamepad.leftTrigger.value)")

			case gamepad.rightTrigger:
				playerRotationY = gamepad.rightTrigger.value - gamepad.leftTrigger.value
				print("Controller: \(index), right trigger: \(gamepad.rightTrigger.value)")

			case gamepad.leftThumbstickButton:
				print("Controller: \(index), left thumbstick button: \(gamepad.leftThumbstickButton?.value)")

			case gamepad.rightThumbstickButton:
				print("Controller: \(index), right thumbstick button: \(gamepad.rightThumbstickButton?.value)")

			case gamepad.buttonOptions: // left auxiliary button, share on PS, view on XBOX One/Seriex X, back on XBox
				print("Controller: \(index), options: \(gamepad.buttonOptions?.value)")

			case gamepad.buttonMenu: // right auxiliary button, options on PS, menu on XBOX One/Series X, start on XBox
				print("Controller: \(index), menu: \(gamepad.buttonMenu.value)")

			default:
				break

		}

	}

	func controllerMotionDetected(motion:GCMotion, index:Int) {
		print("gravity: \(motion.gravity.x), \(motion.gravity.y), \(motion.gravity.z)")
		print("userAcc: \(motion.userAcceleration.x), \(motion.userAcceleration.y), \(motion.userAcceleration.z)")
		print("rotationRate: \(motion.rotationRate.x), \(motion.rotationRate.y), \(motion.rotationRate.z)")
		print("attitude: \(motion.attitude.x), \(motion.attitude.y), \(motion.attitude.z), \(motion.attitude.w)")
	}

}

// Generic matrix math utility functions

func matrix4x4_scale(_ scaleX:Float, _ scaleY:Float, _ scaleZ:Float) -> simd_float4x4 {
	return simd_float4x4.init(columns:(
		simd_float4(scaleX, 0, 0, 0),
		simd_float4(0, scaleY, 0, 0),
		simd_float4(0, 0, scaleZ, 0),
		simd_float4(0, 0, 0, 1)
	))
}

func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
	let unitAxis = normalize(axis)
	let ct = cosf(radians)
	let st = sinf(radians)
	let ci = 1 - ct
	let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
	return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
										 vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
										 vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
										 vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
	return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
										 vector_float4(0, 1, 0, 0),
										 vector_float4(0, 0, 1, 0),
										 vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
	let ys = 1 / tanf(fovy * 0.5)
	let xs = ys / aspectRatio
	let zs = farZ / (nearZ - farZ)
	return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
										 vector_float4( 0, ys, 0,   0),
										 vector_float4( 0,  0, zs, -1),
										 vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
	return (degrees / 180) * .pi
}
