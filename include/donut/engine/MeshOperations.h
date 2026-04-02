#pragma once

#include <unordered_map>

#include <donut/engine/Scene.h>
#include <donut/engine/SceneTypes.h>
#include <donut/engine/HalfEdge.h>


namespace donut::engine
{
	uint32_t getAdjVertexIndex(std::shared_ptr<BufferGroup>& buffers, uint32_t halfEdgeIdx);
	bool GenerateHalfEdgeData(std::shared_ptr<BufferGroup>& buffers);
	bool GenerateAdjacencyIndices(std::shared_ptr<BufferGroup>& buffers);
	void ProcessEdge(
		std::shared_ptr<BufferGroup>& buffers,
		std::unordered_map<EdgeKey, EdgeInfo, EdgeKeyHash>& edgeMap,
		const std::unordered_map<PositionKey, uint32_t, PositionKeyHash>& posMap,
		uint32_t fromVert, uint32_t toVert, uint32_t halfEdgeIdx);
}



