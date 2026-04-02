 #pragma once
 #include <vector>
 #include <unordered_map>
 #include <nvrhi/nvrhi.h>



    constexpr uint32_t INVALID = 0xFFFFFFFF;

    struct Face
    {
        std::vector<uint32_t> halfEdges; // Half-edges making up this face
    };

    struct HalfEdge
    {
        uint32_t vert;
        uint32_t twin;	// Index of the twin half-edge
        uint32_t next;  // Index of the next half-edge
        uint32_t face;  // Index of the face this half-edge belongs to

        bool isBoundary(const std::vector<HalfEdge>& halfEdges) const
        {
            return twin == INVALID;
        }
    };

    struct Edge
    {
        uint32_t a, b;                        // canonical (a < b)
        bool operator==(const Edge& o) const noexcept { return a == o.a && b == o.b; }
    };

    struct EdgeHash
    {
        size_t operator()(const Edge& e) const noexcept {
            return (uint64_t(e.a) << 32) ^ e.b;
        }
    };

    struct EdgeVertKey
    {
        uint32_t v0, v1, step, n;
        bool operator==(const EdgeVertKey& o) const noexcept {
            return v0 == o.v0 && v1 == o.v1 && step == o.step && n == o.n;
        }
    };
    struct EdgeVertKeyHash
    {
        size_t operator()(const EdgeVertKey& k) const {
            size_t h = k.v0; h ^= k.v1 * 2654435761u; h ^= k.step * 2246822519u; h ^= k.n * 3266489917u;
            return h;
        }
    };
    struct PositionKey
    {
        int64_t x, y, z;

        PositionKey(const dm::float3& p)
        {
            const double scale = 1e6;
            x = static_cast<int64_t>(std::round(static_cast<double>(p.x) * scale));
            y = static_cast<int64_t>(std::round(static_cast<double>(p.y) * scale));
            z = static_cast<int64_t>(std::round(static_cast<double>(p.z) * scale));
        }
        
        bool operator==(const PositionKey& other) const
        {
            return x == other.x && y == other.y && z == other.z;
        }
    };
    struct PositionKeyHash
    {
        size_t operator()(const PositionKey& k) const
        {
            size_t h = 0;
            nvrhi::hash_combine(h, k.x);
            nvrhi::hash_combine(h, k.y);
            nvrhi::hash_combine(h, k.z);
            return h;
        }
    };
