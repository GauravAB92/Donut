/*
* Copyright (c) 2014-2024, NVIDIA CORPORATION. All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a
* copy of this software and associated documentation files (the "Software"),
* to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/

#include <donut/render/ERAAPass.h>
#include <donut/render/DrawStrategy.h>
#include <donut/engine/FramebufferFactory.h>
#include <donut/engine/ShaderFactory.h>
#include <donut/engine/ShadowMap.h>
#include <donut/engine/SceneTypes.h>
#include <donut/engine/CommonRenderPasses.h>
#include <donut/engine/MaterialBindingCache.h>
#include <donut/core/log.h>
#include <nvrhi/utils.h>
#include <utility>

#if DONUT_WITH_STATIC_SHADERS
#if DONUT_WITH_DX11
#include "compiled_shaders/passes/cubemap_gs.dxbc.h"
#include "compiled_shaders/passes/forward_ps.dxbc.h"
#include "compiled_shaders/passes/forward_vs_input_assembler.dxbc.h"
#include "compiled_shaders/passes/forward_vs_buffer_loads.dxbc.h"
#endif
#if DONUT_WITH_DX12
#include "compiled_shaders/passes/cubemap_gs.dxil.h"
#include "compiled_shaders/passes/forward_ps.dxil.h"
#include "compiled_shaders/passes/forward_vs_input_assembler.dxil.h"
#include "compiled_shaders/passes/forward_vs_buffer_loads.dxil.h"
#endif
#if DONUT_WITH_VULKAN
#include "compiled_shaders/passes/cubemap_gs.spirv.h"
#include "compiled_shaders/passes/forward_ps.spirv.h"
#include "compiled_shaders/passes/forward_vs_input_assembler.spirv.h"
#include "compiled_shaders/passes/forward_vs_buffer_loads.spirv.h"
#endif
#endif

using namespace donut::math;
#include <donut/shaders/forward_cb.h>
#include <donut/app/DeviceManager.h>


#include <donut/shaders/blit_cb.h>

using namespace donut::engine;
using namespace donut::render;

ERAAPass::ERAAPass(
    nvrhi::IDevice* device,
    std::shared_ptr<CommonRenderPasses> commonPasses)
    : m_Device(device)
    , m_CommonPasses(std::move(commonPasses))
{
    m_IsDX11 = m_Device->getGraphicsAPI() == nvrhi::GraphicsAPI::D3D11;
}

void ERAAPass::Init(ShaderFactory& shaderFactory, const CreateParameters& params)
{
	m_UseGSAdjacency = params.gsAdjacencyMode;

    m_UseInputAssembler = params.useInputAssembler;

    m_SupportedViewTypes = ViewType::PLANAR;
 
    m_RectVS        = shaderFactory.CreateAutoShader("donut/rect_vs.hlsl", "main", DONUT_MAKE_PLATFORM_SHADER(g_rect_vs), nullptr, nvrhi::ShaderType::Vertex);

    std::vector<ShaderMacro> Macros;
    Macros.push_back(ShaderMacro("ERAA_SHOW_DETECTED_EDGES", params.showEdgeData ? "1" : "0"));

    m_EraaResolvePS = shaderFactory.CreateAutoShader("donut/passes/eraa_resolve_ps.hlsl", "main_ps", DONUT_MAKE_PLATFORM_SHADER(g_eraa_resolve_ps), &Macros, nvrhi::ShaderType::Pixel);

    m_VertexShader = CreateVertexShader(shaderFactory, params);
    m_InputLayout = CreateInputLayout(m_VertexShader, params);
    m_GeometryShader = CreateGeometryShader(shaderFactory, params);
    m_PixelShader = CreatePixelShader(shaderFactory, params, false);
    m_PixelShaderTransmissive = CreatePixelShader(shaderFactory, params, true);

    auto samplerDesc = nvrhi::SamplerDesc()
        .setAllAddressModes(nvrhi::SamplerAddressMode::Border)
        .setBorderColor(1.0f);
    m_ShadowSampler = m_Device->createSampler(samplerDesc);

    m_ForwardViewCB = m_Device->createBuffer(nvrhi::utils::CreateVolatileConstantBufferDesc(sizeof(ForwardShadingViewConstants), "ForwardShadingViewConstants", params.numConstantBufferVersions));
    m_ForwardLightCB = m_Device->createBuffer(nvrhi::utils::CreateVolatileConstantBufferDesc(sizeof(ForwardShadingLightConstants), "ForwardShadingLightConstants", params.numConstantBufferVersions));

    m_ViewBindingLayout = CreateViewBindingLayout();
    m_ViewBindingSet = CreateViewBindingSet();
    m_ShadingBindingLayout = CreateShadingBindingLayout();
    m_InputBindingLayout = CreateInputBindingLayout();

    {
        nvrhi::BindingLayoutDesc layoutDesc;
        layoutDesc.visibility = nvrhi::ShaderType::All;
        layoutDesc.bindings = {
            nvrhi::BindingLayoutItem::PushConstants(0, sizeof(BlitConstants)),
            nvrhi::BindingLayoutItem::Texture_SRV(0),
            nvrhi::BindingLayoutItem::Texture_UAV(1),
        };

        m_ResolveBindingLayout = m_Device->createBindingLayout(layoutDesc);
    }

}

void ERAAPass::ResetBindingCache()
{
    m_InputBindingSets.clear();
}

nvrhi::ShaderHandle ERAAPass::CreateVertexShader(ShaderFactory& shaderFactory, const CreateParameters& params)
{
    char const* sourceFileName = "donut/passes/eraa_pass_vs.hlsl";
    
    return shaderFactory.CreateAutoShader(sourceFileName, "main_vs",
        DONUT_MAKE_PLATFORM_SHADER(g_forward_vs), nullptr, nvrhi::ShaderType::Vertex);
} 

nvrhi::ShaderHandle ERAAPass::CreateGeometryShader(ShaderFactory& shaderFactory, const CreateParameters& params)
{


    std::vector<ShaderMacro> Macros;
    Macros.push_back(ShaderMacro("USE_GS_ADJACENCY_DATA", params.showEdgeData ? "1" : "0"));

    if (params.gsAdjacencyMode)
    {
        return shaderFactory.CreateAutoShader("donut/passes/eraa_pass_gs.hlsl", "main_gs_adj", DONUT_MAKE_PLATFORM_SHADER(g_forward_gs_adj), &Macros, nvrhi::ShaderType::Geometry);
    }
    else
    {
        return shaderFactory.CreateAutoShader("donut/passes/eraa_pass_gs.hlsl", "main_gs", DONUT_MAKE_PLATFORM_SHADER(g_forward_gs), &Macros, nvrhi::ShaderType::Geometry);
    }

    return nullptr;
}

nvrhi::ShaderHandle ERAAPass::CreatePixelShader(ShaderFactory& shaderFactory, const CreateParameters& params, bool transmissiveMaterial)
{
    return shaderFactory.CreateAutoShader("donut/passes/eraa_pass_ps.hlsl", "main_ps", DONUT_MAKE_PLATFORM_SHADER(g_forward_ps), nullptr, nvrhi::ShaderType::Pixel);
}

nvrhi::InputLayoutHandle ERAAPass::CreateInputLayout(nvrhi::IShader* vertexShader, const CreateParameters& params)
{
    if (params.useInputAssembler)
    {
        const nvrhi::VertexAttributeDesc inputDescs[] =
        {
            GetVertexAttributeDesc(VertexAttribute::Position, "POS", 0),
            GetVertexAttributeDesc(VertexAttribute::PrevPosition, "PREV_POS", 1),
            GetVertexAttributeDesc(VertexAttribute::TexCoord1, "TEXCOORD", 2),
            GetVertexAttributeDesc(VertexAttribute::Normal, "NORMAL", 3),
            GetVertexAttributeDesc(VertexAttribute::Tangent, "TANGENT", 4),
            GetVertexAttributeDesc(VertexAttribute::Transform, "TRANSFORM", 5),
        };
        return m_Device->createInputLayout(inputDescs, uint32_t(std::size(inputDescs)), vertexShader);
    }
    return nullptr;
}

nvrhi::BindingLayoutHandle ERAAPass::CreateViewBindingLayout()
{
    auto bindingLayoutDesc = nvrhi::BindingLayoutDesc()
        .setVisibility(nvrhi::ShaderType::Vertex | nvrhi::ShaderType::Geometry |  nvrhi::ShaderType::Pixel)
        .setRegisterSpaceAndDescriptorSet(FORWARD_SPACE_VIEW)
        .addItem(nvrhi::BindingLayoutItem::VolatileConstantBuffer(FORWARD_BINDING_VIEW_CONSTANTS));

    return m_Device->createBindingLayout(bindingLayoutDesc);
}


nvrhi::BindingSetHandle ERAAPass::CreateViewBindingSet()
{
    auto bindingSetDesc = nvrhi::BindingSetDesc()
        .setTrackLiveness(m_TrackLiveness)
        .addItem(nvrhi::BindingSetItem::ConstantBuffer(FORWARD_BINDING_VIEW_CONSTANTS, m_ForwardViewCB));

    return m_Device->createBindingSet(bindingSetDesc, m_ViewBindingLayout);
}

nvrhi::BindingLayoutHandle ERAAPass::CreateShadingBindingLayout()
{
    auto bindingLayoutDesc = nvrhi::BindingLayoutDesc()
        .setVisibility(nvrhi::ShaderType::Pixel)
        .setRegisterSpaceAndDescriptorSet(0)
        .addItem(nvrhi::BindingLayoutItem::Texture_UAV(1))
        .addItem(nvrhi::BindingLayoutItem::Texture_UAV(2))
        .addItem(nvrhi::BindingLayoutItem::Texture_UAV(3))
        .addItem(nvrhi::BindingLayoutItem::Texture_UAV(4))
        .addItem(nvrhi::BindingLayoutItem::Texture_UAV(5));

    return m_Device->createBindingLayout(bindingLayoutDesc);
}

void ERAAPass::CreateShadingBindingSet(nvrhi::ITexture* eraaOffsets, nvrhi::ITexture* depthReadTexture, nvrhi::ITexture* depthWriteTexture, nvrhi::ITexture* eraaReadTexture, nvrhi::ITexture* eraaWriteTexture)
{
    auto bindingSetDesc = nvrhi::BindingSetDesc()
        .setTrackLiveness(m_TrackLiveness)
        .addItem(nvrhi::BindingSetItem::Texture_UAV(1, eraaOffsets))
        .addItem(nvrhi::BindingSetItem::Texture_UAV(2, depthReadTexture))
        .addItem(nvrhi::BindingSetItem::Texture_UAV(3, depthWriteTexture))
        .addItem(nvrhi::BindingSetItem::Texture_UAV(4, eraaReadTexture))
        .addItem(nvrhi::BindingSetItem::Texture_UAV(5, eraaWriteTexture));

    m_ShaderBindingSet =  m_Device->createBindingSet(bindingSetDesc, m_ShadingBindingLayout);
}



nvrhi::GraphicsPipelineHandle ERAAPass::CreateGraphicsPipeline(ERAAPassPipelineKey const& key,
    nvrhi::FramebufferInfo const& framebufferInfo)
{
    nvrhi::GraphicsPipelineDesc pipelineDesc;
	pipelineDesc.primType = m_UseGSAdjacency ? nvrhi::PrimitiveType::TriangleListWithAdjacency : nvrhi::PrimitiveType::TriangleList;
    pipelineDesc.inputLayout = m_InputLayout;
    pipelineDesc.VS = m_VertexShader;
    pipelineDesc.GS = m_GeometryShader;
    pipelineDesc.PS = m_PixelShader;
    pipelineDesc.renderState.rasterState.frontCounterClockwise = key.frontCounterClockwise;
    pipelineDesc.renderState.rasterState.setCullMode(key.cullMode);
    pipelineDesc.renderState.rasterState.setConservativeRasterEnable(true);
    pipelineDesc.renderState.depthStencilState.setDepthTestEnable(false);
    pipelineDesc.renderState.depthStencilState.setDepthWriteEnable(false);
 
    pipelineDesc.renderState.depthStencilState
        .setDepthFunc(key.reverseDepth
            ? nvrhi::ComparisonFunc::GreaterOrEqual
            : nvrhi::ComparisonFunc::LessOrEqual);

    pipelineDesc.renderState.blendState.alphaToCoverageEnable = false;
    //pipelineDesc.shadingRateState = key.shadingRateState;
    pipelineDesc.bindingLayouts = {  m_ViewBindingLayout , m_ShadingBindingLayout };
    pipelineDesc.bindingLayouts.push_back(m_InputBindingLayout);

    return m_Device->createGraphicsPipeline(pipelineDesc, framebufferInfo);
}

void ERAAPass::SetupView(
    GeometryPassContext& abstractContext,
    nvrhi::ICommandList* commandList,
    const IView* view,
    const IView* viewPrev)
{
    auto& context = static_cast<Context&>(abstractContext);

    ForwardShadingViewConstants viewConstants = {};
    view->FillPlanarViewConstants(viewConstants.view);
    commandList->writeBuffer(m_ForwardViewCB, &viewConstants, sizeof(viewConstants));

    context.keyTemplate.frontCounterClockwise   = view->IsMirrored();
    context.keyTemplate.reverseDepth            = view->IsReverseDepth();
    context.keyTemplate.shadingRateState        = view->GetVariableRateShadingState();
}

ViewType::Enum ERAAPass::GetSupportedViewTypes() const
{
    return m_SupportedViewTypes;
}

bool ERAAPass::SetupMaterial(GeometryPassContext& abstractContext, const Material* material,
    nvrhi::RasterCullMode cullMode, nvrhi::GraphicsState& state)
{
    auto& context = static_cast<Context&>(abstractContext);

    if (material->domain >= MaterialDomain::Count || cullMode > nvrhi::RasterCullMode::None)
    {
        assert(false);
        return false;
    }

    ERAAPassPipelineKey key = context.keyTemplate;
    key.cullMode = cullMode;
    key.domain = material->domain;

    nvrhi::GraphicsPipelineHandle& pipeline = m_Pipelines[key];

    if (!pipeline)
    {
        std::lock_guard<std::mutex> lockGuard(m_Mutex);

        if (!pipeline)
            pipeline = CreateGraphicsPipeline(key, state.framebuffer->getFramebufferInfo());

        if (!pipeline)
            return false;
    }

    assert(pipeline->getFramebufferInfo() == state.framebuffer->getFramebufferInfo());

    state.pipeline = pipeline;
    state.bindings = { m_ViewBindingSet, m_ShaderBindingSet };

    if (!m_UseInputAssembler)
        state.bindings.push_back(context.inputBindingSet);

    return true;
}

void ERAAPass::SetupInputBuffers(GeometryPassContext& abstractContext, const BufferGroup* buffers, nvrhi::GraphicsState& state)
{
    auto& context = static_cast<Context&>(abstractContext);

    state.indexBuffer = { m_UseGSAdjacency ? buffers->adjIndexBuffer : buffers->indexBuffer, nvrhi::Format::R32_UINT, 0 };

    context.inputBindingSet = GetOrCreateInputBindingSet(buffers);
    context.positionOffset  = uint32_t(buffers->getVertexBufferRange(VertexAttribute::Position).byteOffset);
    context.texCoordOffset  = uint32_t(buffers->getVertexBufferRange(VertexAttribute::TexCoord1).byteOffset);
    context.normalOffset    = uint32_t(buffers->getVertexBufferRange(VertexAttribute::Normal).byteOffset);
    context.tangentOffset   = uint32_t(buffers->getVertexBufferRange(VertexAttribute::Tangent).byteOffset);
}

nvrhi::BindingLayoutHandle ERAAPass::CreateInputBindingLayout()
{
    if (m_UseInputAssembler)
        return nullptr;

    auto bindingLayoutDesc = nvrhi::BindingLayoutDesc()
        .setVisibility(nvrhi::ShaderType::Vertex)
        .setRegisterSpaceAndDescriptorSet(FORWARD_SPACE_INPUT)
        .addItem(m_IsDX11
            ? nvrhi::BindingLayoutItem::RawBuffer_SRV(FORWARD_BINDING_INSTANCE_BUFFER)
            : nvrhi::BindingLayoutItem::StructuredBuffer_SRV(FORWARD_BINDING_INSTANCE_BUFFER))
        .addItem(nvrhi::BindingLayoutItem::RawBuffer_SRV(FORWARD_BINDING_VERTEX_BUFFER))
        .addItem(nvrhi::BindingLayoutItem::PushConstants(FORWARD_BINDING_PUSH_CONSTANTS, sizeof(ForwardPushConstants)));

    return m_Device->createBindingLayout(bindingLayoutDesc);
}

nvrhi::BindingSetHandle ERAAPass::CreateInputBindingSet(const BufferGroup* bufferGroup)
{
    auto bindingSetDesc = nvrhi::BindingSetDesc()
        .addItem(m_IsDX11
            ? nvrhi::BindingSetItem::RawBuffer_SRV(FORWARD_BINDING_INSTANCE_BUFFER, bufferGroup->instanceBuffer)
            : nvrhi::BindingSetItem::StructuredBuffer_SRV(FORWARD_BINDING_INSTANCE_BUFFER, bufferGroup->instanceBuffer))
        .addItem(nvrhi::BindingSetItem::RawBuffer_SRV(FORWARD_BINDING_VERTEX_BUFFER, bufferGroup->vertexBuffer))
        .addItem(nvrhi::BindingSetItem::PushConstants(FORWARD_BINDING_PUSH_CONSTANTS, sizeof(ForwardPushConstants)));

    return m_Device->createBindingSet(bindingSetDesc, m_InputBindingLayout);
}

nvrhi::BindingSetHandle ERAAPass::GetOrCreateInputBindingSet(const BufferGroup* bufferGroup)
{
    auto it = m_InputBindingSets.find(bufferGroup);
    if (it == m_InputBindingSets.end())
    {
        auto bindingSet = CreateInputBindingSet(bufferGroup);
        m_InputBindingSets[bufferGroup] = bindingSet;
        return bindingSet;
    }

    return it->second;
}

void ERAAPass::SetPushConstants(
    donut::render::GeometryPassContext& abstractContext,
    nvrhi::ICommandList* commandList,
    nvrhi::GraphicsState& state,
    nvrhi::DrawArguments& args)
{
    if (m_UseInputAssembler)
        return;

    auto& context = static_cast<Context&>(abstractContext);

    ForwardPushConstants constants;
    constants.startInstanceLocation = args.startInstanceLocation;
    constants.startVertexLocation   = args.startVertexLocation;
    constants.positionOffset        = context.positionOffset;
    constants.texCoordOffset        = context.texCoordOffset;
    constants.normalOffset          = context.normalOffset;
    constants.tangentOffset         = context.tangentOffset;

    commandList->setPushConstants(&constants, sizeof(constants));

    args.startInstanceLocation = 0;
    args.startVertexLocation = 0;
}


void ERAAPass::Resolve(nvrhi::ICommandList* commandList, const ResolveParams& params)
{
    assert(commandList);
    assert(params.targetFramebuffer);
    assert(params.unResolvedTexture);
    assert(params.eraaOffsetsTexture);


    const nvrhi::FramebufferDesc& fbDesc = params.targetFramebuffer->getDesc();
    assert(fbDesc.colorAttachments.size() == 1);
    assert(fbDesc.colorAttachments[0].valid());


    const nvrhi::FramebufferInfoEx& fbinfo = params.targetFramebuffer->getFramebufferInfo();
    const nvrhi::TextureDesc& sourceDesc = params.unResolvedTexture->getDesc();

    assert(sourceDesc.dimension == nvrhi::TextureDimension::Texture2D);


    nvrhi::Viewport targetViewport = params.targetViewport;
    if (targetViewport.width() == 0 && targetViewport.height() == 0)
    {
        // If no viewport is specified, create one based on the framebuffer dimensions.
        // Note that the FB dimensions may not be the same as target texture dimensions, in case a non-zero mip level is used.
        targetViewport = nvrhi::Viewport(float(fbinfo.width), float(fbinfo.height));
    }

    nvrhi::IShader* shader = nullptr;

    if(!m_ResolvePipeline)
    {
        nvrhi::GraphicsPipelineDesc psoDesc;
        psoDesc.bindingLayouts = { m_ResolveBindingLayout };
        psoDesc.VS = m_RectVS;
        psoDesc.PS = m_EraaResolvePS;
        psoDesc.primType = nvrhi::PrimitiveType::TriangleStrip;
        psoDesc.renderState.rasterState.setCullNone();
        psoDesc.renderState.depthStencilState.depthTestEnable = false;
        psoDesc.renderState.depthStencilState.stencilEnable = false;
        m_ResolvePipeline = m_Device->createGraphicsPipeline(psoDesc, params.targetFramebuffer->getFramebufferInfo());
    }

    nvrhi::BindingSetDesc bindingSetDesc;
    {
        auto sourceDimension = sourceDesc.dimension;

        auto sourceSubresources = nvrhi::TextureSubresourceSet(params.sourceMip, 1, params.sourceArraySlice, 1);

        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::PushConstants(0, sizeof(BlitConstants)),
            nvrhi::BindingSetItem::Texture_SRV(0, params.unResolvedTexture,  params.unResolvedTextureFormat, sourceSubresources,  nvrhi::TextureDimension::Texture2D),
            nvrhi::BindingSetItem::Texture_UAV(1, params.eraaOffsetsTexture, params.eraaOffsetsTextureFormat, sourceSubresources,  nvrhi::TextureDimension::Texture2D),
        };
    }

    // If a binding cache is provided, get the binding set from the cache.
    // Otherwise, create one and then release it.
    nvrhi::BindingSetHandle sourceBindingSet;
    sourceBindingSet = m_Device->createBindingSet(bindingSetDesc, m_ResolveBindingLayout);

    nvrhi::GraphicsState state;
    state.pipeline = m_ResolvePipeline;
    state.framebuffer = params.targetFramebuffer;
    state.bindings = { sourceBindingSet };
    state.viewport.addViewport(targetViewport);
    state.viewport.addScissorRect(nvrhi::Rect(targetViewport));


    BlitConstants blitConstants = {};
    blitConstants.sourceOrigin = float2(params.sourceBox.m_mins);
    blitConstants.sourceSize = params.sourceBox.diagonal();
    blitConstants.targetOrigin = float2(params.targetBox.m_mins);
    blitConstants.targetSize = params.targetBox.diagonal();

    commandList->setGraphicsState(state);
    commandList->setPushConstants(&blitConstants, sizeof(blitConstants));

    nvrhi::DrawArguments args;
    args.instanceCount = 1;
    args.vertexCount = 4;
    commandList->draw(args);
}

