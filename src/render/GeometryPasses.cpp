/*
* Copyright (c) 2014-2021, NVIDIA CORPORATION. All rights reserved.
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

#include <donut/render/GeometryPasses.h>
#include <donut/engine/SceneGraph.h>
#include <donut/engine/FramebufferFactory.h>
#include <donut/render/DrawStrategy.h>

using namespace donut::math;
using namespace donut::engine;
using namespace donut::render;

void donut::render::RenderView(
    nvrhi::ICommandList* commandList,
    const IView* view,
    const IView* viewPrev,
    nvrhi::IFramebuffer* framebuffer,
    IDrawStrategy& drawStrategy,
    IGeometryPass& pass,
    GeometryPassContext& passContext,
    bool materialEvents,
    bool singleTriangleMode
    )
{
    pass.SetupView(passContext, commandList, view, viewPrev);

	const DrawItem* lastItem = nullptr;
    const Material* lastMaterial = nullptr;
    const BufferGroup* lastBuffers = nullptr;
    nvrhi::RasterCullMode lastCullMode = nvrhi::RasterCullMode::Back;

    bool drawMaterial = true;
    bool stateValid = false;

    const Material* eventMaterial = nullptr;

    nvrhi::GraphicsState graphicsState;
    graphicsState.framebuffer = framebuffer;
    graphicsState.viewport = view->GetViewportState();
    graphicsState.shadingRateState = view->GetVariableRateShadingState();

    nvrhi::DrawArguments currentDraw;
    currentDraw.instanceCount = 0;

    auto flushDraw = [commandList, materialEvents, &graphicsState, &currentDraw, &eventMaterial, &pass, &passContext](const DrawItem* item)
    {
        if (currentDraw.instanceCount == 0)
            return;

        if (materialEvents && item->material != eventMaterial)
        {
            if (eventMaterial)
                commandList->endMarker();

            if (item->material->name.empty())
            {
                eventMaterial = nullptr;
            }
            else
            {
                commandList->beginMarker(item->material->name.c_str());
                eventMaterial = item->material;
            }
        }

        pass.SetPushConstants(passContext, commandList, graphicsState, currentDraw);
        commandList->drawIndexed(currentDraw);
        currentDraw.instanceCount = 0;
    };
    
    while (const DrawItem* item = drawStrategy.GetNextItem())
    {
        if (item->material == nullptr)
            continue;


        bool newBuffers = item->buffers != lastBuffers;
        bool newMaterial = item->material != lastMaterial || item->cullMode != lastCullMode;

        if (!singleTriangleMode || newBuffers || newMaterial)
        {
            flushDraw(item);
        }

        if (newBuffers)
        {
            pass.SetupInputBuffers(passContext, item->buffers, graphicsState);
            lastBuffers = item->buffers;
            stateValid = false;
        }

        if (newMaterial)
        {
            drawMaterial = pass.SetupMaterial(passContext, item->material, item->cullMode, graphicsState);
			lastItem     = item;
            lastMaterial = item->material;
            lastCullMode = item->cullMode;
            stateValid = false;
        }

        if (drawMaterial)
        {
            if (!stateValid)
            {
                commandList->setGraphicsState(graphicsState);
                stateValid = true;
            }

            if (singleTriangleMode)
            {
                
                uint32_t baseIndex = (item->mesh->indexOffset + item->geometry->indexOffsetInMesh) * 2;
                uint32_t baseVertex = item->mesh->vertexOffset + item->geometry->vertexOffsetInMesh;

                for (uint32_t tri = 0; tri < item->geometry->numIndices * 2; tri += 6)
                {
                    nvrhi::DrawArguments args;
                    args.vertexCount = 6;
                    args.instanceCount = 1;
                    args.startIndexLocation = baseIndex + tri;
                    args.startVertexLocation = baseVertex;
                    args.startInstanceLocation = item->instance->GetInstanceIndex();

                    pass.SetPushConstants(passContext, commandList, graphicsState, args);
                    commandList->drawIndexed(args);
                }
            }
            else
            {
                nvrhi::DrawArguments args;
                args.vertexCount = item->geometry->numIndices;
                args.instanceCount = 1;
                args.startVertexLocation = item->mesh->vertexOffset + item->geometry->vertexOffsetInMesh;
                args.startIndexLocation = item->mesh->indexOffset + item->geometry->indexOffsetInMesh;
                args.startInstanceLocation = item->instance->GetInstanceIndex();

                if (currentDraw.instanceCount > 0 &&
                    currentDraw.startIndexLocation == args.startIndexLocation &&
                    currentDraw.startInstanceLocation + currentDraw.instanceCount == args.startInstanceLocation)
                {
                    currentDraw.instanceCount += 1;
                }
                else
                {
                    flushDraw(item);
                    currentDraw = args;
                }
            }
        }
    }

    flushDraw(lastItem);

    if (materialEvents && eventMaterial)
        commandList->endMarker();
}

void donut::render::RenderCompositeView(
    nvrhi::ICommandList* commandList, 
    const ICompositeView* compositeView, 
    const ICompositeView* compositeViewPrev, 
    FramebufferFactory& framebufferFactory,
    const std::shared_ptr<engine::SceneGraphNode>& rootNode,
    IDrawStrategy& drawStrategy,
    IGeometryPass& pass,
    GeometryPassContext& passContext,
    const char* passEvent, 
    bool materialEvents,
    bool singleTriangleMode)
{
    if (passEvent)
        commandList->beginMarker(passEvent);

    ViewType::Enum supportedViewTypes = pass.GetSupportedViewTypes();

    if (compositeViewPrev)
    {
        // the views must have the same topology
        assert(compositeView->GetNumChildViews(supportedViewTypes) == compositeViewPrev->GetNumChildViews(supportedViewTypes));
    }
    
    for (uint viewIndex = 0; viewIndex < compositeView->GetNumChildViews(supportedViewTypes); viewIndex++)
    {
        const IView* view = compositeView->GetChildView(supportedViewTypes, viewIndex);
        const IView* viewPrev = compositeViewPrev ? compositeViewPrev->GetChildView(supportedViewTypes, viewIndex) : nullptr;

        assert(view != nullptr);

        drawStrategy.PrepareForView(rootNode, *view);

        nvrhi::IFramebuffer* framebuffer = framebufferFactory.GetFramebuffer(*view);

        RenderView(commandList, view, viewPrev, framebuffer, drawStrategy, pass, passContext, materialEvents, singleTriangleMode);
    }

    if (passEvent)
        commandList->endMarker();
}

void donut::render::RenderViewPerTriangle(
    nvrhi::ICommandList* commandList,
    const IView* view,
    FramebufferFactory& framebufferFactory,
    const std::shared_ptr<SceneGraphNode>& rootNode,
    IDrawStrategy& drawStrategy,
    IGeometryPass& pass,
    GeometryPassContext& passContext,
    nvrhi::ITexture* depthRead,
    nvrhi::ITexture* depthWrite,
    nvrhi::ITexture* extentRead,
    nvrhi::ITexture* extentWrite,
    bool useGSAdjacency)
{

    drawStrategy.PrepareForView(rootNode, *view);
    pass.SetupView(passContext, commandList, view, nullptr);
    nvrhi::IFramebuffer* framebuffer = framebufferFactory.GetFramebuffer(*view);


    const Material* lastMaterial = nullptr;
    const BufferGroup* lastBuffers = nullptr;
    nvrhi::RasterCullMode lastCullMode = nvrhi::RasterCullMode::Back;
	const DrawItem* lastItem = nullptr;

    nvrhi::GraphicsState state;
    state.framebuffer = framebuffer;
    state.viewport = view->GetViewportState();

    const uint32_t faceStride = useGSAdjacency ? 6 : 3;
    const uint32_t indexScale = useGSAdjacency ? 2 : 1;

	std::vector<const DrawItem*> drawItems;


    while (const DrawItem* item = drawStrategy.GetNextItem())
    {
        if (!item->material) continue;

        if (item->buffers != lastBuffers)
        {
            pass.SetupInputBuffers(passContext, item->buffers, state);
            lastBuffers = item->buffers;
        }

        if (item->material != lastMaterial || item->cullMode != lastCullMode)
        {
            if (!pass.SetupMaterial(passContext, item->material, item->cullMode, state))
                continue;
            lastMaterial = item->material;
            lastCullMode = item->cullMode;
            lastItem     = item;
        }

        uint32_t baseIndex = (item->mesh->indexOffset + item->geometry->indexOffsetInMesh) * indexScale;
        uint32_t baseVertex = item->mesh->vertexOffset + item->geometry->vertexOffsetInMesh;

        for (uint32_t tri = 0; tri < item->geometry->numIndices * indexScale; tri += faceStride)
        {
            commandList->setGraphicsState(state);

            nvrhi::DrawArguments args;
            args.vertexCount = faceStride;
            args.instanceCount = 1;
            args.startIndexLocation = baseIndex + tri;
            args.startVertexLocation = baseVertex;
            args.startInstanceLocation = item->instance->GetInstanceIndex();

            pass.SetPushConstants(passContext, commandList, state, args);
            commandList->drawIndexed(args);

            commandList->copyTexture(depthRead, nvrhi::TextureSlice(), depthWrite, nvrhi::TextureSlice());
            commandList->copyTexture(extentRead, nvrhi::TextureSlice(), extentWrite, nvrhi::TextureSlice());
        }
    }

    {
        uint32_t baseIndex = (lastItem->mesh->indexOffset + lastItem->geometry->indexOffsetInMesh) * indexScale;
        uint32_t baseVertex = lastItem->mesh->vertexOffset + lastItem->geometry->vertexOffsetInMesh;

        for (uint32_t tri = 0; tri < lastItem->geometry->numIndices * indexScale; tri += faceStride)
        {
            commandList->setGraphicsState(state);

            nvrhi::DrawArguments args;
            args.vertexCount = faceStride;
            args.instanceCount = 1;
            args.startIndexLocation = baseIndex + tri;
            args.startVertexLocation = baseVertex;
            args.startInstanceLocation = lastItem->instance->GetInstanceIndex();

            pass.SetPushConstants(passContext, commandList, state, args);
            commandList->drawIndexed(args);

            commandList->copyTexture(depthRead, nvrhi::TextureSlice(), depthWrite, nvrhi::TextureSlice());
            commandList->copyTexture(extentRead, nvrhi::TextureSlice(), extentWrite, nvrhi::TextureSlice());
        }

    }
}
