#include <donut/engine/MeshOperations.h>
#include <vector>


bool donut::engine::GenerateHalfEdgeData(std::shared_ptr<BufferGroup>& buffers)
{
	
	const uint32_t triCount = static_cast<uint32_t>(buffers->indexData.size() / 3);

	buffers->halfEdgesData.clear();
	buffers->halfEdgesData.reserve(buffers->indexData.size());
	buffers->facesData.clear();
	buffers->facesData.reserve(triCount);

	std::unordered_map<PositionKey, uint32_t, PositionKeyHash> positionMap;

	for (uint32_t i = 0; i < buffers->positionData.size(); i++)
	{
		PositionKey key(buffers->positionData[i]);
		if (positionMap.find(key) == positionMap.end())
		{
			positionMap[key] = i;
		}
	}

	// Map Edge to HalfEdgeInfo
	std::unordered_map<EdgeKey, EdgeInfo, EdgeKeyHash> edgeMap;
	edgeMap.reserve(buffers->indexData.size());

	// For each triangle we create half-edges
	for (uint32_t triIdx = 0; triIdx < triCount; ++triIdx)
	{
		uint32_t v0 = buffers->indexData[triIdx * 3 + 0];
		uint32_t v1 = buffers->indexData[triIdx * 3 + 1];
		uint32_t v2 = buffers->indexData[triIdx * 3 + 2];

		// Create face
		Face face;
		uint32_t he0Idx = (uint32_t)buffers->halfEdgesData.size();
		uint32_t he1Idx = (uint32_t)he0Idx + 1;
		uint32_t he2Idx = (uint32_t)he0Idx + 2;
		face.halfEdges = { he0Idx, he1Idx, he2Idx };

		uint32_t faceIdx = (uint32_t)buffers->facesData.size();
		buffers->facesData.push_back(face);

		// Create half-edges
		HalfEdge he0, he1, he2;

		//he0: v0 -> v1
		he0.vert = v1;
		he0.next = face.halfEdges[1];
		he0.face = faceIdx;
		he0.twin = INVALID; //To be set later

		//he1: v1 -> v2
		he1.vert = v2;
		he1.next = face.halfEdges[2];
		he1.face = faceIdx;
		he1.twin = INVALID; //To be set later

		//he2: v2 -> v0
		he2.vert = v0;
		he2.next = face.halfEdges[0];
		he2.face = faceIdx;
		he2.twin = INVALID; //To be set later

		buffers->halfEdgesData.push_back(he0);
		buffers->halfEdgesData.push_back(he1);
		buffers->halfEdgesData.push_back(he2);

		//Register edges and find twins
		ProcessEdge(buffers, edgeMap, positionMap, v0, v1, face.halfEdges[0]);
		ProcessEdge(buffers, edgeMap, positionMap, v1, v2, face.halfEdges[1]);
		ProcessEdge(buffers, edgeMap, positionMap, v2, v0, face.halfEdges[2]);
	}

	return true;
}

uint32_t donut::engine::getAdjVertexIndex(std::shared_ptr<BufferGroup>& buffers, uint32_t halfEdgeIdx)
{
	uint32_t twinIdx = buffers->halfEdgesData[halfEdgeIdx].twin;
	uint32_t vertIdx = INVALID;
	if (twinIdx != INVALID)
	{
		uint32_t nextIdx = buffers->halfEdgesData[twinIdx].next;
		vertIdx = buffers->halfEdgesData[nextIdx].vert;
	}
	else
	{
		//Boundary edge, use the original vertex
		vertIdx = buffers->halfEdgesData[halfEdgeIdx].vert;
	}

	return vertIdx;
}

bool donut::engine::GenerateAdjacencyIndices(std::shared_ptr<BufferGroup>& buffers)
{
	
	buffers->adjIndexData.clear();

	for (auto& face : buffers->facesData)
	{
		uint32_t he0 = face.halfEdges[0];
		uint32_t he1 = face.halfEdges[1];
		uint32_t he2 = face.halfEdges[2];

		// push v0 v0_adj v1 v1_adj v2 v2_adj
		buffers->adjIndexData.push_back(buffers->halfEdgesData[he2].vert);
		buffers->adjIndexData.push_back(getAdjVertexIndex(buffers, he0));
		buffers->adjIndexData.push_back(buffers->halfEdgesData[he0].vert);
		buffers->adjIndexData.push_back(getAdjVertexIndex(buffers, he1));
		buffers->adjIndexData.push_back(buffers->halfEdgesData[he1].vert);
		buffers->adjIndexData.push_back(getAdjVertexIndex(buffers, he2));
	}
	
	return true;
}


void donut::engine::ProcessEdge(
	std::shared_ptr<BufferGroup>& buffers,
	std::unordered_map<EdgeKey, EdgeInfo, EdgeKeyHash>& edgeMap,
	const std::unordered_map<PositionKey, uint32_t, PositionKeyHash>& posMap,
	uint32_t fromVert, uint32_t toVert, uint32_t halfEdgeIdx)
{
	EdgeKey key(fromVert, toVert, buffers->positionData, posMap);
	auto it = edgeMap.find(key);

	if (it == edgeMap.end())
	{
		EdgeInfo edgeInfo;
		edgeInfo.halfEdgeIdx = halfEdgeIdx;
		edgeInfo.fromVert = fromVert;
		edgeMap[key] = edgeInfo;
	}
	else
	{
		EdgeInfo& existing = it->second;
		uint32_t twinHalfEdgeIdx = existing.halfEdgeIdx;

		// Set twin indices
		buffers->halfEdgesData[halfEdgeIdx].twin = twinHalfEdgeIdx;
		buffers->halfEdgesData[twinHalfEdgeIdx].twin = halfEdgeIdx;
		edgeMap.erase(it);
	}
}
