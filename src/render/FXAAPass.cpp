#include <donut/render/FXAAPass.h>
#include <donut/engine/FramebufferFactory.h>
#include <donut/engine/ShaderFactory.h>
#include <donut/engine/CommonRenderPasses.h>
#include <donut/engine/View.h>

using namespace donut::math;

#include <donut/shaders/blit_cb.h>
#include <nvrhi/utils.h>
#include <assert.h>

using namespace donut::engine;
using namespace donut::render;

struct FXAAConstantsAligned
{
	BlitConstants base;
	float2  inverseScreenSize;
	float      padding[53];
};

FXAAPass::FXAAPass(nvrhi::IDevice* device, 
	std::shared_ptr<ShaderFactory> shaderFactory, 
	std::shared_ptr<CommonRenderPasses> commonPasses, 
	std::shared_ptr<FramebufferFactory> framebufferFactory,  
	const ICompositeView& compositeView)
	: m_Device(device),
	m_FramebufferFactory(framebufferFactory),
	m_CommonPasses(commonPasses)
{	
	//Constant Buffer creation
	nvrhi::BufferDesc constantBufferDesc;
	constantBufferDesc.byteSize = sizeof(FXAAConstantsAligned);
	constantBufferDesc.debugName = "FXAAConstantBuffer";
	constantBufferDesc.isConstantBuffer = true;
	constantBufferDesc.isVolatile = true;

	m_ConstantBuffer = m_Device->createBuffer(constantBufferDesc);
	
	//Binding Layout
	nvrhi::BindingLayoutDesc layoutDesc;
	layoutDesc.visibility = nvrhi::ShaderType::AllGraphics;
	layoutDesc.bindings = {
		nvrhi::BindingLayoutItem::VolatileConstantBuffer(0),
		nvrhi::BindingLayoutItem::Texture_SRV(0),
		nvrhi::BindingLayoutItem::Sampler(0)
	};
	m_bindingLayout = m_Device->createBindingLayout(layoutDesc);

	//Build shaders
	m_PixelShader = shaderFactory->CreateAutoShader("donut/passes/fxaa_ps.hlsl", "FXAA_PS", DONUT_MAKE_PLATFORM_SHADER(g_fxaa_ps), nullptr, nvrhi::ShaderType::Pixel);

	//Create bilinear sampler
	nvrhi::SamplerDesc samplerDesc;
	samplerDesc.addressU = samplerDesc.addressV = samplerDesc.addressW = nvrhi::SamplerAddressMode::Clamp;
	samplerDesc.borderColor = nvrhi::Color(0.0f);

	samplerDesc.minFilter = true; // Enables Linear Minification
	samplerDesc.magFilter = true; // Enables Linear Magnification
	samplerDesc.mipFilter = true; // Enables Linear Mip-Sensing

	m_BilinearSampler = m_Device->createSampler(samplerDesc);

	//PSO
	nvrhi::GraphicsPipelineDesc pipelineDesc;
	pipelineDesc.VS = commonPasses->m_RectVS;
	pipelineDesc.PS = m_PixelShader;
	pipelineDesc.bindingLayouts = { m_bindingLayout };
	pipelineDesc.primType = nvrhi::PrimitiveType::TriangleStrip;

	pipelineDesc.renderState.rasterState.setCullNone();
	pipelineDesc.renderState.depthStencilState.depthTestEnable = false;
	pipelineDesc.renderState.depthStencilState.stencilEnable = false;

	nvrhi::FramebufferInfo framebufferInfo = m_FramebufferFactory->GetFramebufferInfo();

	m_Pipeline = m_Device->createGraphicsPipeline(pipelineDesc, framebufferInfo);
}

void FXAAPass::Resolve(nvrhi::ICommandList* commandList, const engine::ICompositeView& compositeView, nvrhi::ITexture* unresolvedColor)
{
	assert(m_Pipeline);

	const nvrhi::TextureDesc& unresolvedColorDesc = unresolvedColor->getDesc();

	//BindingSet
	nvrhi::BindingSetHandle& bindingSet = m_BindingSets[unresolvedColor];

	if (!bindingSet)
	{
		nvrhi::BindingSetDesc bindingSetDesc;
		bindingSetDesc.bindings = {
			nvrhi::BindingSetItem::ConstantBuffer(0, m_ConstantBuffer),
			nvrhi::BindingSetItem::Texture_SRV(0, unresolvedColor),
			nvrhi::BindingSetItem::Sampler(0, m_BilinearSampler)
		};

		bindingSet = m_Device->createBindingSet(bindingSetDesc, m_bindingLayout);
	}

	commandList->beginMarker("FXAA");

	for (uint viewIndex = 0; viewIndex < compositeView.GetNumChildViews(ViewType::PLANAR); viewIndex++)
	{
		const IView* view = compositeView.GetChildView(ViewType::PLANAR, viewIndex);

		const nvrhi::ViewportState viewportState = view->GetViewportState();

		assert(viewportState.viewports.size() == 1);

		const nvrhi::Viewport& inputViewport = viewportState.viewports[0];
		m_ResolvedColorSize.x = unresolvedColor->getDesc().width;
		m_ResolvedColorSize.y = unresolvedColor->getDesc().height;

		BlitConstants blitConstants;

		blitConstants.sourceOrigin = float2(0.5 * (1.0f / m_ResolvedColorSize.x), 0.25 * (1.0f / m_ResolvedColorSize.y));
		blitConstants.sourceSize = m_ResolvedColorSize;
		blitConstants.targetOrigin = float2(0, 0);
		blitConstants.targetSize = m_ResolvedColorSize;
		blitConstants.sharpenFactor = 0.0f;

		FXAAConstantsAligned fxaaConstants;

		fxaaConstants.base = blitConstants;

		fxaaConstants.inverseScreenSize = float2(1.0f / m_ResolvedColorSize.x, 1.0f / m_ResolvedColorSize.y);

		commandList->writeBuffer(m_ConstantBuffer, &fxaaConstants, sizeof(fxaaConstants));

		nvrhi::GraphicsState state;
		state.pipeline = m_Pipeline;
		state.framebuffer = m_FramebufferFactory->GetFramebuffer(*view);
		state.bindings = { bindingSet };
		state.viewport = viewportState;
		commandList->setGraphicsState(state);

		nvrhi::DrawArguments args;
		args.instanceCount = 1;
		args.vertexCount = 4;
		commandList->draw(args);
	}
	commandList->endMarker();
}


