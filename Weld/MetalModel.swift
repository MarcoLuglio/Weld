//
//  MetalModel.swift
//  Weld
//
//  Created by Marco Luglio on 28/05/20.
//  Copyright © 2020 Marco Luglio. All rights reserved.
//

import MetalKit
import ModelIO

import simd



class MetalModel {

	let debugGroup:String

	var meshes:[MTKMesh]

	var modelMatrix:simd_float4x4
	var viewMatrix:simd_float4x4
	var modelViewMatrix:simd_float4x4

	// Multiply: T * R * S (applies scale, then rotation, then translation)

	var scaleX:Float = 1
	var scaleY:Float = 1
	var scaleZ:Float = 1

	var rotationX:Float = 0
	var rotationY:Float = 0
	var rotationZ:Float = 0

	var translationX:Float = 0
	var translationY:Float = 0
	var translationZ:Float = 0

	init(resource:String, mdlVertexDescriptor:MDLVertexDescriptor, debugGroup:String, device: MTLDevice) { // do I need init?

		self.debugGroup = debugGroup
		let modelURL = Bundle.main.url(forResource: resource, withExtension: "obj")! // resource is the name of the file
		let bufferAllocator = MTKMeshBufferAllocator(device: device)
		let asset = MDLAsset(url: modelURL, vertexDescriptor: mdlVertexDescriptor, bufferAllocator: bufferAllocator) // FIXME complains about mtl file, I think it might not be an error per se

		self.meshes = []

		do {
			(_, meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
		} catch {
			fatalError("Could not extract meshes from Model I/O asset")
		}

		let identityMatrix = simd_float4x4.init(columns:(
			simd_float4(1, 0, 0, 0),
			simd_float4(0, 1, 0, 0),
			simd_float4(0, 0, 1, 0),
			simd_float4(0, 0, 0, 1)
		))

		self.modelMatrix = identityMatrix
		self.viewMatrix = identityMatrix
		self.modelViewMatrix = identityMatrix

	}

	func update() {

		//self.translationZ = 0;

		let modelScaleMatrix = matrix4x4_scale(self.scaleX, self.scaleY, self.scaleZ)
		let modelRotationAxis = SIMD3<Float>(0, 1, 0) // TODO actually calculate this
		let modelRotationMatrix = matrix4x4_rotation(
			radians: radians_from_degrees(self.rotationY),
			axis: modelRotationAxis
		)
		let modelTranslationMatrix = matrix4x4_translation(self.translationX, self.translationY, self.translationZ)

		// this order will make the translation happen first, then the rotation
		// the rotation will happen in place
		self.modelMatrix = simd_mul(modelScaleMatrix, modelRotationMatrix)
		self.modelMatrix = simd_mul(modelTranslationMatrix, self.modelMatrix) // for the rotation to happen before, switch the order of the factors here

		let viewRotationAxis = SIMD3<Float>(0, 1, 0)
		let viewRotationMatrix = matrix4x4_rotation(
			radians: radians_from_degrees(0),
			axis: viewRotationAxis
		)

		let viewTranslationMatrix = matrix4x4_translation(0, 0, 0)
		self.viewMatrix = simd_mul(viewRotationMatrix, viewTranslationMatrix)

		self.modelViewMatrix = simd_mul(self.viewMatrix, self.modelMatrix)

	}

	func draw(_ renderCommandEncoder: MTLRenderCommandEncoder, projectionMatrix:simd_float4x4) {

		var uniforms = Uniforms(modelViewMatrix: self.modelViewMatrix, projectionMatrix: projectionMatrix)
		renderCommandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1) // sends the [[buffer(1)]] to the vertex shader function

		for mesh in self.meshes {

			renderCommandEncoder.pushDebugGroup(self.debugGroup)

			let vertexBuffer = mesh.vertexBuffers.first!
			renderCommandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
			// renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
			// renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)

			for submesh in mesh.submeshes {

				let indexBuffer = submesh.indexBuffer

				renderCommandEncoder.drawIndexedPrimitives(
					type: submesh.primitiveType,
					indexCount: submesh.indexCount,
					indexType: submesh.indexType,
					indexBuffer: indexBuffer.buffer,
					indexBufferOffset: indexBuffer.offset
				)

			}

			renderCommandEncoder.popDebugGroup()

		}

	}

}
