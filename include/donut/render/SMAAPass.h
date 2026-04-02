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
	class SMAAPass
	{
	private:
		std::shared_ptr<engine::CommonRenderPasses>		m_CommonPasses;

		std::shared_ptr<engine::FramebufferFactory>		m_EdgesBuffer;
		std::shared_ptr<engine::FramebufferFactory>		m_WeightsBuffer;
		std::shared_ptr<engine::FramebufferFactory>		m_BlendBuffer;
		std::shared_ptr<engine::FramebufferFactory>		m_ResolveBuffer1;
		std::shared_ptr<engine::FramebufferFactory>		m_ResolveBuffer2;


		nvrhi::TextureHandle							m_AreaTexture;
		nvrhi::TextureHandle							m_SearchTexture;

		nvrhi::BufferHandle								m_ConstantBuffer;

		nvrhi::GraphicsPipelineHandle 			m_EdgesPSO;
		nvrhi::GraphicsPipelineHandle			m_WeightsPSO;
		nvrhi::GraphicsPipelineHandle			m_BlendPSO;
		nvrhi::GraphicsPipelineHandle			m_ResolvePSO;


		nvrhi::ShaderHandle						m_VSEdgeDetection;
		nvrhi::ShaderHandle						m_PSEdgeDetection;

		nvrhi::ShaderHandle						m_VSWeightsCalc;
		nvrhi::ShaderHandle						m_PSWeightsCalc;

		nvrhi::ShaderHandle						m_VSNeighborBlend;
		nvrhi::ShaderHandle						m_PSNeighborBlend;

		nvrhi::ShaderHandle						m_VSTemporalResolve;
		nvrhi::ShaderHandle						m_PSTemporalResolve;

		nvrhi::BindingLayoutHandle				m_BindingLayoutShared;
		nvrhi::BindingSetHandle					m_BindingSetShared;

		nvrhi::BindingLayoutHandle				m_BindingLayoutEdgeDetection;
		nvrhi::BindingSetHandle					m_BindingSetEdgeDetection;

		nvrhi::BindingLayoutHandle				m_BindingLayoutWeightsCalc;
		nvrhi::BindingSetHandle					m_BindingSetWeightsCalc;

		nvrhi::BindingLayoutHandle				m_BindingLayoutNeighborBlend;
		nvrhi::BindingSetHandle					m_BindingSetNeighborBlend;

		nvrhi::BindingLayoutHandle				m_BindingLayoutResolve;
		nvrhi::BindingSetHandle					m_BindingSetResolveA;
		nvrhi::BindingSetHandle					m_BindingSetResolveB;

		nvrhi::DeviceHandle						m_Device;

		bool m_firstFrame = true;

	public:
		struct CreateParameters
		{
			nvrhi::ITexture* unresolvedColor = nullptr;
			nvrhi::ITexture* edgesTexture = nullptr;
			nvrhi::ITexture* weightsTexture = nullptr;
			nvrhi::ITexture* motionVectorsTex = nullptr;
			nvrhi::ITexture* blendTex = nullptr;
			nvrhi::ITexture* resolveTex1 = nullptr;
			nvrhi::ITexture* resolveTex2 = nullptr;

			std::shared_ptr<engine::FramebufferFactory>		edgesBuffer;
			std::shared_ptr<engine::FramebufferFactory>		weightsBuffer;
			std::shared_ptr<engine::FramebufferFactory>		blendBuffer;
			std::shared_ptr<engine::FramebufferFactory>		resolveBuffer1;
			std::shared_ptr<engine::FramebufferFactory>		resolveBuffer2;

		};

		SMAAPass(nvrhi::IDevice* device,
			nvrhi::ICommandList* commandList,
			std::shared_ptr<engine::ShaderFactory> shaderFactory,
			std::shared_ptr<engine::CommonRenderPasses> commonPasses,
			const engine::ICompositeView& compositeView,
			const CreateParameters& params);

		void Resolve(
			nvrhi::ICommandList* commandList,
			const engine::ICompositeView& compositeView
		);


		void AdvanceFrame();
		dm::float2 GetCurrentPixelOffset();

		int m_FrameIndex = 0;


	};
}
