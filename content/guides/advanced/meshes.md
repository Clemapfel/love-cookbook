## 0.1 Creating a Mesh Rectangle

```lua
-- initialization
local x, y, w, h = 50, 50, 200, 300 -- top left xy, width, height
local r, g, b, a = 1, 1, 1, 1 -- color: pure white
local rectangle = love.graphics.newMesh({
    { x + 0, y + 0, 0, 0, r, g, b, a },
    { x + w, y + 0, 1, 0, r, g, b, a },
    { x + w, y + h, 1, 1, r, g, b, a },
    { x + 0, y + h, 0, 1, r, g, b, a },
}, "fan", "dynamic")

local texture = love.graphics.newTexture("assets/toast.jpg")
rectangle:setTexture(texture)

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(rectangle)
end 
```

---

### 0.2 Creating a Mesh Circle

```lua
-- initialization
local x, y, xr, yr = 200, 200, 100, 100 -- center xy, x-radius, y-radius
local vertexCount = 64 -- number of outer vertices
local r, g, b, a = 1, 1, 1, 1 -- color: pure white

local circle -- love.Mesh
do
    local vertices = {}
    local circle_data = {}
    for i = 1, vertexCount do
        local angle = (i - 1) / vertexCount * 2 * math.pi
        table.insert(circle_data, {
            x + math.cos(angle) * xr, -- x
            y + math.sin(angle) * yr, -- y
            math.cos(angle), -- u
            math.sin(angle), -- v
            r, g, b, a
        })
    end

    circle = love.graphics.newMesh(circle_data, "fan", "dynamic")
end

-- drawing
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(circle)
end
```
---

### 0.3 Creating a Polygon Mesh using Triangulation

```lua
-- format: { x1, y1, x2, y2, ... }
local input = {
    167.8622990257, 0,
    141.37412207129, 153.70547063563,
    -41.827243725195, 198.73007856213,
    -187.28713855132, 102.30176491128,
    -159.32457952398, -89.182472409685,
    -39.483305587746, -162.49970086587,
    148.0247332512, -152.10238729167,
}

local success, triangles = pcall(love.math.triangulate, input)
if success == false then
    -- handle error, polygon cannot be triangulated because it is non-convex
end

local polygon -- love.Mesh
do
    -- get bounding box for texture coordinate calculation
    local xMin, yMin = math.huge, math.huge
    local xMax, yMax = -math.huge, -math.huge
    for i = 1, #input, 2 do
        local x = input[i + 0]
        local y = input[i + 1]
        xMin = math.min(xMin, x)
        yMin = math.min(yMin, y)
        xMax = math.max(xMax, x)
        yMax = math.max(yMax, y)
    end
    
    -- convert vertex position to texture coordinate
    local xy2uv = function(x, y)
        return (x - xMin) / (xMax - xMin),
        (y - yMin) / (yMax - yMin)
    end
    
    local vertex_data = {}
    local r, g, b, a = 1, 1, 1, 1
    
    -- iterate each vertex of each triangle, and add it as a mesh vertex
    for _, triangle in ipairs(triangles) do
        -- `triangles` format: {{ x1, y1, ...}, {x1, y1 ...}, ... }
        for i = 1, #triangle, 2 do
            -- `triangle` format: { x1, y1, x2, y2, x3, y3 }
            local x = triangle[i + 0]
            local y = triangle[i + 1]
            local u, v = xy2uv(x, y)
            table.insert(vertex_data, {
                x, y, u, v, r, g, b, a
            })
        end
    end
    
    polygon = love.graphics.newMesh(vertex_data, "triangles", "dynamic")
end 

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(polygon)
end
```
---

### 0.4.1 Updating Mesh Data: Single Vertex
```lua
-- vertex data for a rectangle
local x, y, w, h = 50, 50, 200, 300 -- top left xy, width, height
local r, g, b, a = 1, 1, 1, 1
local vertexData = {
    { -- vertex #1
        x + 0, y + 0, -- attribute #1: position (2 components)
        0, 0,         -- attribute #2: texture coordinates (2 components
        r, g, b, a    -- attribute #3: color (4 components)
    },
    { x + w, y + 0, 1, 0, r, g, b, a }, -- vertex #2
    { x + w, y + h, 1, 1, r, g, b, a }, -- vertex #3
    { x + 0, y + h, 0, 1, r, g, b, a }, -- vertex #4
}

local mesh = love.graphics.newMesh(vertexData, "fan",
    "stream"  -- buffer mode stream because it will be updated often
)
local texture = love.graphics.newTexture("assets/toast.png")
mesh:setTexture(texture)

-- modifying vertices

local vertexIndex = 1

-- setting vertex position
local xNew, yNew = 45, 50 -- in pixel coordaintes
mesh:setVertexAttribute(vertexIndex,
    1, -- vertex attribute #1: position
    xNew, yNew -- position has 2 components
)

-- setting vertex texture coordinates
local uNew, vNew = 0.25, 0.8 -- in texture coordinates, normalized in [0, 1]
mesh:setVertexAttribute(vertexIndex,
    2, -- vertex attribute #2: texture coordinates
    uNew, vNew -- texture coordinates have 2 components
)

-- setting vertex color
local rNew, gNew, bNew, aNew = 1, 0, 1, 1 -- color components for magenta
mesh:setVertexAttribute(vertexIndex,
    3, -- vertex attribute #3: color
    rNew, gNew, bNew, aNew -- color has 4 components
)

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end
```
---

### 0.4.1 Updating Mesh Data: All Vertices
```lua
-- vertex data for a rectangle
local x, y, w, h = 50, 50, 200, 300 -- top left xy, width, height
local r, g, b, a = 1, 1, 1, 1
local vertexData = {
    { -- vertex #1
        x + 0, y + 0, -- attribute #1: position (2 components)
        0, 0,         -- attribute #2: texture coordinates (2 components
        r, g, b, a    -- attribute #3: color (4 components)
    },
    { x + w, y + 0, 1, 0, r, g, b, a }, -- vertex #2
    { x + w, y + h, 1, 1, r, g, b, a }, -- vertex #3
    { x + 0, y + h, 0, 1, r, g, b, a }, -- vertex #4
}

local mesh = love.graphics.newMesh(vertexData, "fan",
    "stream"  -- buffer mode stream because it will be updated often
)
local texture = love.graphics.newTexture("assets/toast.png")
mesh:setTexture(texture)

-- modifying vertices

local vertexIndex = 1

-- setting vertex position
local xNew, yNew = 45, 50 -- in pixel coordaintes
local uNew, vNew = 0.25, 0.8 -- in texture coordinates, normalized in [0, 1]
local rNew, gNew, bNew, aNew = 1, 0, 1, 1 -- color components for magenta

-- modify CPU-Side vertexData, this does not update the mesh
vertexData[vertexIndex] = { 
    xNew, yNew, -- attribute #1: vertex position
    uNew, vNew, -- attribute #2: texture coordinates
    rNew, gNew, bNew, aNew  -- attribute #3: color
}

-- now upload to GPU
mesh:setVertices(vertexData)

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end
```
---

### 0.5 Using a Custom Vertex Format with an Index Buffer

> [!CAUTION]
> This is the vertex format for LÖVE 12.0 and later, it will not work in prior versions

```lua
-- create out custom mesh format
local customFormat = {
    {
        location = 0, -- attribute location is 0-based, not 1-based
        name = "VertexDirection", -- CPU-side name
        format = "floatvec2" -- GPU format: 2-component float
    },
    {
        location = 1,
        name = "VertexScale",
        format = "float" -- GPU format: 1-component float
    }
}

-- fill mesh data according to format
local mesh = love.graphics.newMesh(customFormat, {
    {
        -1, -1, -- attribute #1: direction (2 components)
        100,   -- attribute #2: scale (1 component)
    },
    {  1, -1, 120 },  -- x, y, scale
    {  1,  1, 80 },
    { -1,  1, 94 }
}, "triangles", "static")

-- setup triangle index buffer
--  (1)-------(2)
--   | \       |
--   |   \ T1  |
--   | T2  \   |
--   |       \ |
--  (4)-------(3)
mesh:setVertexMap(
    1, 2, 3, -- T1
    1, 3, 4  -- T2
)

-- to draw a mesh with a custom format, we need a custom shader
local shader = love.graphics.newShader(custom.glsl) -- see code below

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    love.graphics.translate(200, 200) -- transforms still work
    love.graphics.draw(mesh)
    love.graphics.setShader(nil)
end
```

```glsl

#ifdef VERTEX
layout (location = 0) in vec2 VertexDirection; // attribute #0: VertexDirection (floatvec2)
layout (location = 1) in float VertexScale; // attribute #1: VertexScale (float)

out vec4 VaryingTexCoord; // default love2d texture coordinate out
out vec4 VaryingColor;    // default love2d color out
// these names are hardcoded by love, they have to be this exactly

void vertexmain() {
    // compute position from custom vertex attributes
    vec2 position = VertexDirection.xy * VertexScale;

    // set texture coords to default value
    VaryingTexCoord = vec4(0.0, 0.0, 0.0, 0.0); // uv is texture coords, zw is padding

    // set color to default value
    VaryingColor = vec4(1.0, 1.0, 1.0, 1.0); // r g b a

    // set position
    love_Position = TransformProjectionMatrix * vec4(position.xy, 0.0, 1.0);
}

// because we assigned `VaryingTexCoord`, `VaryingColor` and `love_Position`,
// which are the default love names, the fragment shader works like always
#endif

#ifdef PIXEL
vec4 effect(vec4 vertexColor, sampler2D img, vec2 textureCoordinates, vec2 fragmentPosition) {
    return vertexColor * texture(img, textureCoordinates);
}
#endif
```
---

### 0.6 Attaching Mesh Attributes for Geometry Instancing

```lua
local instanceMeshFormat = {
    {
        location = 0,
        name = "VertexPosition",
        format = "floatvec2"
    },

    {
        location = 1,
        name = "VertexTexCoords",
        format = "floatvec2"
    },

    {
        location = 2,
        name = "VertexColor",
        format = "floatvec4"
    }
}

local instanceMesh = love.graphics.newMesh(instanceMeshFormat,{
    {
        -1, -1, -- instance attribute #1: position (2 components)
        0,  0, -- instance attribute #2: texture coords (2 components)
        1, 1, 1, 1 -- instance attribute #3: color (4 components)
        -- no attribute 4!
    },
    {  1, -1,  1, 0,  1, 1, 1, 1 },  -- xy, uv, rgba
    {  1,  1,  1, 1,  1, 1, 1, 1 },
    { -1,  1,  0, 1,  1, 1, 1, 1 }
}, "fan", "static") -- host is static, it will never be updated

local dataMeshFormat = {
    {
        location = 3, -- start attribute location at #4, because instanceMesh had 3 attribute
        name = "InstanceOffset",
        format = "floatvec2"
    },

    {
        location = 4,
        name = "InstanceScale",
        format = "float"
    }
}

local dataMeshData = {
    {
        0, 0, -- attribute #1: offset (2 components)
        1 -- attribute #2: scale (1 component)
    }
}

-- fill rest of data mesh algorithmically
local instanceCount = 2000

-- instance properties
local xMin, yMin = 50, 50
local xMax, yMax = love.graphics.getWidth() - 50, love.graphics.getHeight() - 50
local sizeMin, sizeMax = 1, 7

-- generate random number in range
local rng = function(min, max)
    return min + math.random() * (max - min)
end

for i = 1, instanceCount do
    local x, y = rng(xMin, xMax), rng(yMin, yMax)
    local size = rng(sizeMin, sizeMax)

    table.insert(dataMeshData, {
        x, y, -- data mesh attribute #1: offset
        size  -- data mesh attribute #2: size
    })
end


local dataMesh = love.graphics.newMesh(
    dataMeshFormat,
    dataMeshData,
    "points", -- draw mode (unused)
    "stream" -- buffer mod
)

-- attach the data mesh to the instance mesh
for _, formatEntry in pairs(dataMeshFormat) do
    instanceMesh:attachAttribute( -- mesh to attach *to*
        formatEntry.name, -- attribute name
        dataMesh,         -- mesh to attach *from*
        "perinstance"     -- attachment mode: 1 vertex attribute array in data mesh per 1 instance when drawing
    )
end

-- we need a custom shader 
local shader = love.graphics.newShader(instance.glsl); -- see code below

-- usage
love.draw = function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    love.graphics.drawInstanced(instanceMesh, instanceCount)
    love.graphics.setShader(nil)
end

-- update only data mesh and upload
love.update = function(delta)
    local maxOffset = 50
    for _, entry in ipairs(dataMeshData) do
        local x, y, scale = (unpack or table.unpack)(entry)

        -- move instance position randomly
        entry[1] = x + rng(-1, 1) * maxOffset * delta
        entry[2] = y + rng(-1, 1) * maxOffset * delta
    end

    -- upload
    dataMesh:setVertices(dataMeshData)
end
```
```glsl
// instance.glsl
#ifdef VERTEX

// instance mesh attributes
layout (location = 0) in vec2 VertexPosition;  // instance mesh attribute #1: position
layout (location = 1) in vec2 VertexTexCoord;  // instance mesh attribute #2: texture coords
layout (location = 2) in vec4 VertexColor;     // instance mesh attribute #3: color

// data mesh attributes
layout (location = 3) in vec2 InstanceOffset;  // data mesh attribute #1: offset
layout (location = 4) in float InstanceScale;  // data mesh attribute #2: scale

out vec4 VaryingTexCoord; // default love2d texture coordinate out
out vec4 VaryingColor;    // default love2d color out
// these names are hardcoded by love, they have to be this exactly

void vertexmain() {
    // compute position from custom vertex attributes
    vec2 position = VertexPosition;
    position.xy *= InstanceScale;
    position.xy += InstanceOffset;

    // set texture coords to default value
    VaryingTexCoord = vec4(VertexTexCoord.xy, 1.0, 1.0); // uv, zw is padding

    // set color to default value
    VaryingColor = VertexColor; // rgba

    // set position
    love_Position = TransformProjectionMatrix * vec4(position.xy, 0.0, 1.0);
}
#endif
```
---