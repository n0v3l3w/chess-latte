local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local lplayer = Players.LocalPlayer

local function get_offsets()
    local t = {}
    for k, v in game:HttpGet("https://offsets.ntgetwritewatch.workers.dev/offsets.json"):gmatch('"([^"]-)"%s*:%s*"([^"]-)"') do
        t[k] = v
    end
    return t
end

local function parseHex(val)
    if type(val) == "string" then
        return tonumber(val, 16) or tonumber(val)
    end
    return nil
end

local rawOffsets = get_offsets()

local Offsets = {
    DisplayName  = parseHex(rawOffsets["DisplayName"]),
    FrameVisible = parseHex(rawOffsets["FrameVisible"]),
}

local displayName = memory_read("string", lplayer.Address + Offsets.DisplayName)

if game.PlaceId ~= 6222531507 then
    notify("This script is for Chess (PlaceId 6222531507). You are in the wrong game.", "Wrong Game", 10)
    return
end

loadstring(game:HttpGet('https://raw.githubusercontent.com/n0v3l3w/chess-latte/refs/heads/main/x11-colorpicker.lua'))()
local UILib = UILib

local Config = {
    Depth = 17,
    ThinkTime = 100,
    DisregardThinkTime = false,
}

local State = {
    Status = "Idle",
    LastOutput = "",
    Running = true,
}

local PieceMap = {
    Pawn   = "p",
    Knight = "n",
    Bishop = "b",
    Rook   = "r",
    Queen  = "q",
    King   = "k",
}

local Board = {}
Board.__index = Board

function Board.new()
    local self = setmetatable({}, Board)
    return self
end

function Board.gameInProgress()
    local piecesFolder = Workspace:FindFirstChild("Pieces")
    if not piecesFolder then return false end
    return #piecesFolder:GetChildren() > 0
end

local function getTilePosition(boardTile)
    if not boardTile then return nil end

    if boardTile.ClassName == "Model" then
        local meshTile = boardTile:FindFirstChild("Meshes/tile_a")
        if meshTile then return meshTile.Position end

        local tilePart = boardTile:FindFirstChild("Tile")
        if tilePart then return tilePart.Position end

        local primary = boardTile.PrimaryPart
        if primary then return primary.Position end

        return nil
    end

    return boardTile.Position
end

local function getPiecePosition(piece)
    if not piece then return nil end

    local primary = nil

    local ok1, res1 = pcall(function()
        return piece:FindFirstChildOfClass("MeshPart")
    end)
    if ok1 and res1 then primary = res1 end

    if not primary then
        local ok2, res2 = pcall(function()
            return piece:FindFirstChildOfClass("Part")
        end)
        if ok2 and res2 then primary = res2 end
    end

    if primary then return primary.Position end

    local ok3, pos = pcall(function()
        return piece.Position
    end)
    if ok3 then return pos end

    return nil
end

local cachedTilePositions = nil

local function cacheTilePositions()
    local boardFolder = Workspace:FindFirstChild("Board")
    if not boardFolder then return nil end

    local positions = {}

    for x = 1,8 do
        for y = 1,8 do
            local tileName = tostring(x) .. "," .. tostring(y)
            local tile = boardFolder:FindFirstChild(tileName)
            local pos = getTilePosition(tile)
            if pos then
                positions[tileName] = { pos = pos, x = x, y = y }
            end
        end
    end

    cachedTilePositions = positions
    return positions
end

local function findTileForPiece(piecePos, tileCache)
    if not piecePos then return nil,nil end

    local bestDist = math.huge
    local bestX, bestY

    for _, tileData in pairs(tileCache) do
        local dx = piecePos.X - tileData.pos.X
        local dz = piecePos.Z - tileData.pos.Z
        local dist = dx*dx + dz*dz

        if dist < bestDist then
            bestDist = dist
            bestX = tileData.x
            bestY = tileData.y
        end
    end

    if bestDist < 16 then
        return bestX, bestY
    end

    return nil,nil
end

function Board.getPiece(tileName)
    local piecesFolder = Workspace:FindFirstChild("Pieces")
    if not piecesFolder then return nil end

    local tileCache = cachedTilePositions or cacheTilePositions()
    if not tileCache then return nil end

    local tileData = tileCache[tileName]
    if not tileData then return nil end

    local targetPos = tileData.pos
    local bestDist = math.huge
    local bestPiece = nil

    for _,piece in ipairs(piecesFolder:GetChildren()) do
        local piecePos = getPiecePosition(piece)

        if piecePos then
            local dx = piecePos.X - targetPos.X
            local dz = piecePos.Z - targetPos.Z
            local dist = dx*dx + dz*dz

            if dist < bestDist then
                bestDist = dist
                bestPiece = piece
            end
        end
    end

    if bestDist < 16 then
        return bestPiece
    end

    return nil
end

local _gameStatus = lplayer:FindFirstChild("PlayerGui"):FindFirstChild("GameStatus")
local _white = _gameStatus:FindFirstChild("White")
local _black = _gameStatus:FindFirstChild("Black")

local function _isVisible(instance)
    return memory_read("byte", instance.Address + Offsets.FrameVisible) == 1
end

function Board:getLocalTeam()
    local whiteInfo = _white:FindFirstChild("Info")
    local blackInfo = _black:FindFirstChild("Info")

    if whiteInfo and (string.find(whiteInfo.Text, lplayer.Name) or string.find(whiteInfo.Text, displayName)) then
        return "w"
    end

    if blackInfo and (string.find(blackInfo.Text, lplayer.Name) or string.find(blackInfo.Text, displayName)) then
        return "b"
    end

    return nil
end

function Board:isPlayerTurn()
    local team = self:getLocalTeam()
    if not team then return false end

    local frame = (team == "w") and _white or _black
    return _isVisible(frame)
end

function Board:willCauseDesync()
    return not self:isPlayerTurn()
end

function Board:_scanBoard()
    local piecesFolder = Workspace:FindFirstChild("Pieces")
    if not piecesFolder then return nil end

    local tileCache = cachedTilePositions or cacheTilePositions()
    if not tileCache then return nil end

    local boardState = {}
    for x=1,8 do boardState[x] = {} end

    for _,piece in ipairs(piecesFolder:GetChildren()) do
        local pieceChar = PieceMap[piece.Name]
        if pieceChar then
            local piecePos = getPiecePosition(piece)
            local x,y = findTileForPiece(piecePos, tileCache)

            if x and y then
                local isWhite = false
                local primaryPart

                local ok1,res1 = pcall(function() return piece:FindFirstChildOfClass("MeshPart") end)
                if ok1 and res1 then primaryPart = res1 end

                if not primaryPart then
                    local ok2,res2 = pcall(function() return piece:FindFirstChildOfClass("Part") end)
                    if ok2 and res2 then primaryPart = res2 end
                end

                if primaryPart then
                    local colorOk,color = pcall(function() return primaryPart.Color end)
                    if colorOk and color then
                        local r,g,b = color.R, color.G, color.B
                        if r>1 or g>1 or b>1 then r,g,b = r/255, g/255, b/255 end
                        isWhite = (r+g+b)/3 > 0.5
                    end
                end

                boardState[x][y] = isWhite and string.upper(pieceChar) or pieceChar
            end
        end
    end

    return boardState
end

function Board:board2fen()
    local boardPieces = self:_scanBoard()
    if not boardPieces then return nil end

    local result = ""

    for y=8,1,-1 do
        local empty = 0
        for x=8,1,-1 do
            if not boardPieces[x] then boardPieces[x] = {} end
            local piece = boardPieces[x][y]

            if piece and piece ~= "" then
                if empty > 0 then
                    result = result .. tostring(empty)
                    empty = 0
                end
                result = result .. piece
            else
                empty = empty + 1
            end
        end

        if empty > 0 then result = result .. tostring(empty) end
        if y ~= 1 then result = result .. "/" end
    end

    result = result .. " " .. (self:getLocalTeam() or "w")
    return result
end

local function urlEncode(str)
    local encoded = ""
    for i=1,#str do
        local c = string.sub(str,i,i)
        local b = string.byte(c)
        if (b>=48 and b<=57) or (b>=65 and b<=90) or (b>=97 and b<=122)
        or c=="-" or c=="_" or c=="." or c=="~" then
            encoded = encoded .. c
        else
            encoded = encoded .. string.format("%%%02X", b)
        end
    end
    return encoded
end

local function getPosFromResult(result)
    local x1 = 9 - (string.byte(result,1) - 96)
    local y1 = tonumber(string.sub(result,2,2))
    local x2 = 9 - (string.byte(result,3) - 96)
    local y2 = tonumber(string.sub(result,4,4))
    return x1,y1,x2,y2
end

local Highlights = {}

local function destroyAllHighlights()
    for _,h in ipairs(Highlights) do
        pcall(function() h.circle:Remove() end)
    end
    Highlights = {}
end

local function highlightInstance(target)
    pcall(function()
        local pos = getPiecePosition(target) or getTilePosition(target)

        if not pos then
            local rawOk,rawPos = pcall(function() return target.Position end)
            if rawOk then pos = rawPos end
        end

        if not pos then return end

        local circle = Drawing.new("Circle")
        circle.Radius = 20
        circle.Color = Color3.fromRGB(59,235,223)
        circle.Thickness = 3
        circle.Filled = false
        circle.Visible = false

        table.insert(Highlights, { circle = circle, target = target, worldPos = pos })
    end)
end

local function updateHighlights()
    for _,h in ipairs(Highlights) do
        local pos = getPiecePosition(h.target) or getTilePosition(h.target) or h.worldPos
        local screenPos,onScreen = WorldToScreen(pos)
        h.circle.Visible = onScreen
        if onScreen then h.circle.Position = screenPos end
    end
end

local function findBestMove(board)
    if not board:isPlayerTurn() then return {false,"Not your turn"} end
    if board:willCauseDesync() then return {false,"Will cause desync"} end

    local fen = board:board2fen()
    if not fen then return {false,"Could not read board"} end

    local encodedFen = urlEncode(fen)
    local url = "http://127.0.0.1:3000/api/solve?fen=" .. encodedFen
        .. "&depth=" .. tostring(Config.Depth)
        .. "&max_think_time=" .. tostring(Config.ThinkTime)
        .. "&disregard_think_time=" .. tostring(Config.DisregardThinkTime)

    local ok,ret = pcall(function() return game:HttpGet(url) end)
    if not ok then return {false,"HttpGet failed: "..tostring(ret)} end
    if not ret or ret=="" then return {false,"Empty response from Stockfish server"} end

    -- Parse response with gmatch (Matcha has no JSONDecode)
    local success = ret:match('"success"%s*:%s*(true)')
    local result  = ret:match('"result"%s*:%s*"([^"]+)"')

    if not success then
        return {false, result or "Unknown error"}
    end

    if not result then return {false,"No result in response"} end

    local x1,y1,x2,y2 = getPosFromResult(result)

    local pieceToMove = Board.getPiece(tostring(x1)..","..tostring(y1))
    if not pieceToMove then return {false,"No piece to move"} end

    local boardFolder = Workspace:FindFirstChild("Board")
    local placeToMove = boardFolder and boardFolder:FindFirstChild(tostring(x2)..","..tostring(y2))
    if not placeToMove then return {false,"No place to move to"} end

    return {true, result, pieceToMove, placeToMove}
end

local board = Board.new()

local function runBestMove()
    State.Status = "Calculating"
    State.LastOutput = ""

    local output = findBestMove(board)

    if output[1] == false then
        State.Status = "Error!"
        State.LastOutput = tostring(output[2])

        task.spawn(function()
            task.wait(2.5)
            if State.Status == "Error!" then State.Status = "Idle" end
        end)

        return
    end

    destroyAllHighlights()
    highlightInstance(output[3])
    highlightInstance(output[4])

    State.Status = "Idle"
    State.LastOutput = "Best: "..tostring(output[2])

    task.spawn(function()
        while board:isPlayerTurn() do task.wait() end
        destroyAllHighlights()
    end)
end

destroyAllHighlights()

local function getStatusText()
    return "Status: "..State.Status
end

local function getOutputText()
    if #State.LastOutput > 0 then return State.LastOutput end
    return nil
end

local myGui = UILib.new("Chess", Vector2.new(320,380), {getStatusText,getOutputText})

local engineTab = myGui:Tab("Engine")
local settingsSection = myGui:Section(engineTab,"Settings")

myGui:Slider(engineTab,settingsSection,"Depth",Config.Depth,function(value)
    Config.Depth = value
end,1,30,1,"")

myGui:Slider(engineTab,settingsSection,"Think Time",Config.ThinkTime,function(value)
    Config.ThinkTime = value
end,10,5000,10,"ms")

myGui:Checkbox(engineTab,settingsSection,"Disregard Time",Config.DisregardThinkTime,function(state)
    Config.DisregardThinkTime = state
end)

local controlsSection = myGui:Section(engineTab,"Controls")

myGui:Button(engineTab,controlsSection,"Calculate",function()
    task.spawn(runBestMove)
end)

myGui:Keybind(engineTab,controlsSection,"Calc Key","r",function(state)
    if state then task.spawn(runBestMove) end
end,"Hold")

myGui:Checkbox(engineTab,controlsSection,"Unload",false,function(state)
    if state then State.Running = false end
end)

myGui:CreateSettingsTab()

notify("Chess script loaded! Use the x11 menu to configure.", "Chess Script", 5)

while State.Running do
    updateHighlights()
    myGui:Step()
    wait(0.0015)
end

destroyAllHighlights()
myGui:Destroy()
