#pragma once


#include <donut/render/GeometryPasses.h>
#include <donut/engine/SceneTypes.h>
#include <nvrhi/nvrhi.h>
#include <memory>


namespace donut::render
{
	class ERAAPass : public IGeometryPass
	{

	public:
        // IGeometryPass implementation
        [[nodiscard]] engine::ViewType::Enum GetSupportedViewTypes() const override;
        void SetupView(GeometryPassContext& context, nvrhi::ICommandList* commandList,
            const engine::IView* view, const engine::IView* viewPrev) override;
        bool SetupMaterial(GeometryPassContext& context, const engine::Material* material,
            nvrhi::RasterCullMode cullMode, nvrhi::GraphicsState& state) override;
        void SetupInputBuffers(GeometryPassContext& context, const engine::BufferGroup* buffers,
            nvrhi::GraphicsState& state) override;
        void SetPushConstants(GeometryPassContext& context, nvrhi::ICommandList* commandList,
            nvrhi::GraphicsState& state, nvrhi::DrawArguments& args) override;
	};
}
