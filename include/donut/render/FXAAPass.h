#pragma once

#include <donut/core/math/math.h>
#include <nvrhi/nvrhi.h>
#include <memory>
#include <unordered_map>


namespace donut::engine
{
	class ShaderFactory;
	class ShadowMap;
	class CommonRenderPasses;
	class FramebufferFactory;
	class ICompositeView;
}

namespace donut::render
{
	class FXAAPass
	{
	private:
		std::shared_ptr<engine::CommonRenderPasses> m_CommonPasses;

		nvrhi::TextureHandle					m_ColorBufferTexture;

		nvrhi::BindingLayoutHandle				m_bindingLayout;

		std::unordered_map<nvrhi::ITexture*, nvrhi::BindingSetHandle> m_BindingSets;

		nvrhi::ShaderHandle						m_VertexShader;         //Access vertex shader  bytecode
		nvrhi::ShaderHandle						m_PixelShader;          //Access pixel  shader  bytecode
		
		nvrhi::SamplerHandle					m_BilinearSampler;

		nvrhi::BufferHandle						m_ConstantBuffer;

		std::shared_ptr<engine::FramebufferFactory>		m_FramebufferFactory;

		nvrhi::GraphicsPipelineHandle			m_Pipeline;

		dm::float2 m_ResolvedColorSize;

		nvrhi::DeviceHandle							m_Device;


	public:

		FXAAPass(nvrhi::IDevice* device,
			std::shared_ptr<engine::ShaderFactory> shaderFactory,
			std::shared_ptr<engine::CommonRenderPasses> commonPasses,
			std::shared_ptr<engine::FramebufferFactory> framebufferFactory,
			const engine::ICompositeView& compositeView,
			bool debugEdges);

		void Resolve(nvrhi::ICommandList* commandList,
			const engine::ICompositeView& compositeView,
			nvrhi::ITexture* unresolvedColor);
		
	
	};
}
