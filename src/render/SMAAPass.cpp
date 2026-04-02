#include <donut/render/SMAAPass.h>
#include <donut/engine/FramebufferFactory.h>
#include <donut/engine/ShaderFactory.h>
#include <donut/engine/CommonRenderPasses.h>
#include <donut/engine/View.h>
#include <donut/render/AreaTex.h>
#include <donut/render/SearchTex.h>

using namespace donut::math;

#include <nvrhi/utils.h>
#include <assert.h>

using namespace donut::engine;
using namespace donut::render;

struct SMAAConstantsAligned
{
	float4 subsampleIndices;
	float4 rtMetrics;
	float      padding[56];
};

SMAAPass::SMAAPass(
	nvrhi::IDevice* device,
	nvrhi::ICommandList* commandList,
	std::shared_ptr<ShaderFactory> shaderFactory,
	std::shared_ptr<CommonRenderPasses> commonPasses,
	const ICompositeView& compositeView,
	const CreateParameters& params
)
	: m_CommonPasses(commonPasses)
	, m_FrameIndex(0)
	, m_Device(device)
	, m_EdgesBuffer(params.edgesBuffer)
	, m_WeightsBuffer(params.weightsBuffer)
	, m_BlendBuffer(params.blendBuffer)
	, m_ResolveBuffer1(params.resolveBuffer1)
	, m_ResolveBuffer2(params.resolveBuffer2)
{
	const nvrhi::TextureDesc& feedback1Desc = params.resolveTex1->getDesc();
	const nvrhi::TextureDesc& feedback2Desc = params.resolveTex2->getDesc();

	assert(feedback1Desc.width == feedback2Desc.width);
	assert(feedback1Desc.height == feedback2Desc.height);
	assert(feedback1Desc.format == feedback2Desc.format);


	//Shaders
	m_VSEdgeDetection = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "EdgeDetectionVS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_edge_vs), nullptr, nvrhi::ShaderType::Vertex);
	m_PSEdgeDetection = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "EdgeDetectionPS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_edge_ps), nullptr, nvrhi::ShaderType::Pixel);

	m_VSWeightsCalc = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "WeightsCalcVS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_weights_vs), nullptr, nvrhi::ShaderType::Vertex);
	m_PSWeightsCalc = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "WeightsCalcPS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_weights_ps), nullptr, nvrhi::ShaderType::Pixel);

	m_VSNeighborBlend = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "NeighborBlendVS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_blend_vs), nullptr, nvrhi::ShaderType::Vertex);
	m_PSNeighborBlend = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "NeighborBlendPS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_blend_ps), nullptr, nvrhi::ShaderType::Pixel);

	m_VSTemporalResolve = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "TemporalResolveVS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_resolve_vs), nullptr, nvrhi::ShaderType::Vertex);
	m_PSTemporalResolve = shaderFactory->CreateAutoShader("donut/passes/smaa_shaders.hlsl", "TemporalResolvePS", DONUT_MAKE_PLATFORM_SHADER(g_smaa_resolve_ps), nullptr, nvrhi::ShaderType::Pixel);

	//Constant Buffer
	nvrhi::BufferDesc constantBufferDesc;
	constantBufferDesc.byteSize = sizeof(SMAAConstantsAligned);
	constantBufferDesc.debugName = "SMAAConstantBuffer";
	constantBufferDesc.keepInitialState = true;
	constantBufferDesc.initialState = nvrhi::ResourceStates::ConstantBuffer;
	constantBufferDesc.isConstantBuffer = true;

	m_ConstantBuffer = m_Device->createBuffer(constantBufferDesc);

	//Load precomputed textures
		//Area Texture
	{
		nvrhi::TextureDesc textureDesc;
		textureDesc.format = nvrhi::Format::RG8_UNORM;
		textureDesc.isRenderTarget = false;
		textureDesc.width = AREATEX_WIDTH;
		textureDesc.height = AREATEX_HEIGHT;
		textureDesc.dimension = nvrhi::TextureDimension::Texture2D;
		textureDesc.initialState = nvrhi::ResourceStates::ShaderResource;
		textureDesc.keepInitialState = true;
		textureDesc.debugName = "Area Texture";
		textureDesc.sampleCount = 1;

		m_AreaTexture = m_Device->createTexture(textureDesc);

		commandList->open();
		commandList->writeTexture(m_AreaTexture, 0, 0, areaTexBytes, AREATEX_PITCH);
		commandList->close();
		m_Device->executeCommandList(commandList);
	}

	//Search Texture
	{
		nvrhi::TextureDesc textureDesc;
		textureDesc.format = nvrhi::Format::R8_UNORM;
		textureDesc.isRenderTarget = false;
		textureDesc.width = SEARCHTEX_WIDTH;
		textureDesc.height = SEARCHTEX_HEIGHT;
		textureDesc.dimension = nvrhi::TextureDimension::Texture2D;
		textureDesc.initialState = nvrhi::ResourceStates::ShaderResource;
		textureDesc.keepInitialState = true;
		textureDesc.debugName = "Search Texture";
		textureDesc.sampleCount = 1;

		m_SearchTexture = m_Device->createTexture(textureDesc);

		commandList->open();
		commandList->writeTexture(m_SearchTexture, 0, 0, searchTexBytes, SEARCHTEX_PITCH);
		commandList->close();
		m_Device->executeCommandList(commandList);
	}

	//Bindings
	{ //Shared
		nvrhi::BindingSetDesc bindingSetDesc;
		bindingSetDesc.bindings =
		{
			nvrhi::BindingSetItem::ConstantBuffer(0, m_ConstantBuffer),
			nvrhi::BindingSetItem::Sampler(0, m_CommonPasses->m_LinearClampSampler),
			nvrhi::BindingSetItem::Sampler(1, m_CommonPasses->m_PointClampSampler),
		};

		nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingSetDesc, m_BindingLayoutShared, m_BindingSetShared);
	}

	{ //Edge Detection
		nvrhi::BindingSetDesc bindingSetDesc;
		bindingSetDesc.bindings =
		{
			nvrhi::BindingSetItem::Texture_SRV(0, params.unresolvedColor), // colorTexGamma
		};

		nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingSetDesc, m_BindingLayoutEdgeDetection, m_BindingSetEdgeDetection);
	}

	{ //Weights Calculation
		nvrhi::BindingSetDesc bindingSetDesc;
		bindingSetDesc.bindings =
		{
			nvrhi::BindingSetItem::Texture_SRV(0, params.edgesTexture), // edgesTex
			nvrhi::BindingSetItem::Texture_SRV(1, m_AreaTexture), // areaTex
			nvrhi::BindingSetItem::Texture_SRV(2, m_SearchTexture), // searchTex
		};

		nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingSetDesc, m_BindingLayoutWeightsCalc, m_BindingSetWeightsCalc);
	}

	{ //Neighbor Blend
		nvrhi::BindingSetDesc bindingSetDesc;
		bindingSetDesc.bindings =
		{
			nvrhi::BindingSetItem::Texture_SRV(0, params.unresolvedColor), // colorTex
			nvrhi::BindingSetItem::Texture_SRV(1, params.weightsTexture), // blendTex
			nvrhi::BindingSetItem::Texture_SRV(2, params.motionVectorsTex), // motionVectorsTex
		};

		nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingSetDesc, m_BindingLayoutNeighborBlend, m_BindingSetNeighborBlend);
	}

	{ //Temporal Resolve
		nvrhi::BindingLayoutDesc bindingLayoutDesc;
		bindingLayoutDesc.visibility = nvrhi::ShaderType::AllGraphics;
		bindingLayoutDesc.bindings = {
			nvrhi::BindingLayoutItem::Texture_SRV(0),
			nvrhi::BindingLayoutItem::Texture_SRV(1),
			nvrhi::BindingLayoutItem::Texture_SRV(2),
		};

		m_BindingLayoutResolve = device->createBindingLayout(bindingLayoutDesc);

		nvrhi::BindingSetDesc bindingSetDesc;
		bindingSetDesc.bindings =
		{
			nvrhi::BindingSetItem::Texture_SRV(0, params.blendTex), // currentFrameTex
			nvrhi::BindingSetItem::Texture_SRV(1, params.resolveTex1), // previousFrameTex
			nvrhi::BindingSetItem::Texture_SRV(2, params.motionVectorsTex), // motionVectorsTex
		};
		m_BindingSetResolveA = device->createBindingSet(bindingSetDesc, m_BindingLayoutResolve);

		bindingSetDesc.bindings[1].resourceHandle = params.resolveTex2;
		m_BindingSetResolveB = device->createBindingSet(bindingSetDesc, m_BindingLayoutResolve);
	}

	//PSOs
	{ //Edges
		nvrhi::GraphicsPipelineDesc psoDesc;
		psoDesc.VS = m_VSEdgeDetection;
		psoDesc.PS = m_PSEdgeDetection;
		psoDesc.bindingLayouts = { m_BindingLayoutShared, m_BindingLayoutEdgeDetection };
		psoDesc.primType = nvrhi::PrimitiveType::TriangleList;
		psoDesc.renderState.rasterState.setCullNone();
		psoDesc.renderState.depthStencilState.depthTestEnable = false;
		psoDesc.renderState.depthStencilState.stencilEnable = false;

		nvrhi::FramebufferInfo framebufferInfo = m_EdgesBuffer->GetFramebufferInfo();

		m_EdgesPSO = device->createGraphicsPipeline(psoDesc, framebufferInfo);
	}

	{ //Weights
		nvrhi::GraphicsPipelineDesc psoDesc;
		psoDesc.VS = m_VSWeightsCalc;
		psoDesc.PS = m_PSWeightsCalc;
		psoDesc.bindingLayouts = { m_BindingLayoutShared, m_BindingLayoutWeightsCalc };
		psoDesc.primType = nvrhi::PrimitiveType::TriangleStrip;
		psoDesc.renderState.rasterState.setCullNone();
		psoDesc.renderState.depthStencilState.depthTestEnable = false;
		psoDesc.renderState.depthStencilState.stencilEnable = false;

		nvrhi::FramebufferInfo framebufferInfo = m_WeightsBuffer->GetFramebufferInfo();

		m_WeightsPSO = device->createGraphicsPipeline(psoDesc, framebufferInfo);
	}

	{ //Blend
		nvrhi::GraphicsPipelineDesc psoDesc;
		psoDesc.VS = m_VSNeighborBlend;
		psoDesc.PS = m_PSNeighborBlend;
		psoDesc.bindingLayouts = { m_BindingLayoutShared, m_BindingLayoutNeighborBlend };
		psoDesc.primType = nvrhi::PrimitiveType::TriangleStrip;
		psoDesc.renderState.rasterState.setCullNone();
		psoDesc.renderState.depthStencilState.depthTestEnable = false;
		psoDesc.renderState.depthStencilState.stencilEnable = false;

		nvrhi::FramebufferInfo framebufferInfo = m_BlendBuffer->GetFramebufferInfo();
		m_BlendPSO = device->createGraphicsPipeline(psoDesc, framebufferInfo);
	}

	{ //Resolve
		nvrhi::GraphicsPipelineDesc psoDesc;
		psoDesc.VS = m_VSTemporalResolve;
		psoDesc.PS = m_PSTemporalResolve;
		psoDesc.bindingLayouts = { m_BindingLayoutShared, m_BindingLayoutResolve };
		psoDesc.primType = nvrhi::PrimitiveType::TriangleStrip;
		psoDesc.renderState.rasterState.setCullNone();
		psoDesc.renderState.depthStencilState.depthTestEnable = false;
		psoDesc.renderState.depthStencilState.stencilEnable = false;

		nvrhi::FramebufferInfo framebufferInfo = m_ResolveBuffer1->GetFramebufferInfo();

		m_ResolvePSO = device->createGraphicsPipeline(psoDesc, framebufferInfo);
	}

}

void donut::render::SMAAPass::Resolve(nvrhi::ICommandList* commandList, const engine::ICompositeView& compositeView)
{
	assert(m_EdgesPSO);
	assert(m_WeightsPSO);
	assert(m_BlendPSO);

	commandList->beginMarker("SMAA");
	for (uint viewIndex = 0; viewIndex < compositeView.GetNumChildViews(ViewType::PLANAR); viewIndex++)
	{
		const IView* view = compositeView.GetChildView(ViewType::PLANAR, viewIndex);

		const nvrhi::ViewportState viewportState = view->GetViewportState();

		assert(viewportState.viewports.size() == 1);

		const nvrhi::Viewport& inputViewport = viewportState.viewports[0];

		SMAAConstantsAligned smaaConstants;
		smaaConstants.subsampleIndices = m_FrameIndex == 0 ? float4(
			1.0f, 1.0f, 1.f, 0.0f
		)
			: float4(
				2.0f, 2.0f, 2.0f, 0.0f
			);

		smaaConstants.rtMetrics = float4(
			1.0f / inputViewport.width(), 1.0f / inputViewport.height(),
			inputViewport.width(), inputViewport.height()
		);

		commandList->writeBuffer(m_ConstantBuffer, &smaaConstants, sizeof(SMAAConstantsAligned));

		//Edge Detection
		{
			nvrhi::GraphicsState state;
			state.pipeline = m_EdgesPSO;
			state.framebuffer = m_EdgesBuffer->GetFramebuffer(*view);
			state.bindings = { m_BindingSetShared, m_BindingSetEdgeDetection };
			state.viewport = viewportState;
			commandList->setGraphicsState(state);

			nvrhi::DrawArguments args;
			args.instanceCount = 1;
			args.vertexCount = 3;
			commandList->draw(args);
		}

		//Weights Calculation
		{
			nvrhi::GraphicsState state;
			state.pipeline = m_WeightsPSO;
			state.framebuffer = m_WeightsBuffer->GetFramebuffer(*view);
			state.bindings = { m_BindingSetShared, m_BindingSetWeightsCalc };
			state.viewport = viewportState;
			commandList->setGraphicsState(state);

			nvrhi::DrawArguments args;
			args.instanceCount = 1;
			args.vertexCount = 3;
			commandList->draw(args);
		}

		//Blending
		{
			nvrhi::GraphicsState state;
			state.pipeline = m_BlendPSO;
			state.framebuffer = m_BlendBuffer->GetFramebuffer(*view);
			state.bindings = { m_BindingSetShared,  m_BindingSetNeighborBlend };
			state.viewport = viewportState;
			commandList->setGraphicsState(state);

			nvrhi::DrawArguments args;
			args.instanceCount = 1;
			args.vertexCount = 3;
			commandList->draw(args);
		}

		//Resolve Temporally
		{
			nvrhi::GraphicsState state;
			state.pipeline = m_ResolvePSO;
			state.framebuffer = m_FrameIndex == 0 ? m_ResolveBuffer2->GetFramebuffer(*view) : m_ResolveBuffer1->GetFramebuffer(*view);
			state.bindings = { m_BindingSetShared,  m_FrameIndex == 0 ? m_BindingSetResolveA : m_BindingSetResolveB };
			state.viewport = viewportState;
			commandList->setGraphicsState(state);

			nvrhi::DrawArguments args;
			args.instanceCount = 1;
			args.vertexCount = 3;
			commandList->draw(args);
		}
	}
	commandList->endMarker();

}

void SMAAPass::AdvanceFrame()
{
	m_FrameIndex = (m_FrameIndex + 1) % 2;
}

float2 SMAAPass::GetCurrentPixelOffset()
{
	return (m_FrameIndex == 0) ? float2(-0.25f, 0.25f) : float2(0.25f, -0.25f);

}