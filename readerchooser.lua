require "font"
require "keys"
require "settings"
require "screen"
require "pdfreader"
require "djvureader"
require "koptreader"
require "picviewer"
require "crereader"
require "defaults"
require "gettext"

registry = {
	-- registry format:
	-- reader_name = {reader_object, supported_formats, priority}
	PDFReader  = {PDFReader, DPDFREADER_EXT, 1},
	DJVUReader = {DJVUReader, DDJVUREADER_EXT, 1},
	PDFReflow = {KOPTReader, DPDFREFLOW_EXT, 2},
	DJVUReflow = {KOPTReader, DDJVUREFLOW_EXT, 2},
	CREReader  = {CREReader, DCREREADER_EXT, 2},
	PICViewer = {PICViewer, DPICVIEWER_EXT, 1},
}

ReaderChooser = {
	-- UI constants
	title_H = 35,	-- title height
	title_bar_H = 15, -- title bar height
	options_H = 35, -- options height
	options_bar_T = 2, -- options bar thickness
	spacing = 35,	-- spacing between lines
	WIDTH = 380,    -- window width
	HEIGHT = 220,   -- window height
	margin_I = 50,  -- reader item margin
	margin_O = 10,  -- option margin
	title_font_size = 23,  -- title font size
	item_font_size = 20,   -- reader item font size
	option_font_size = 17, -- option font size

    BGCOLOR = 3, -- background color

	-- title text
	TITLE = _("Complete action using"),
	-- options text
	OPTION_TYPE = _("Remember this type(T)"),
	OPTION_FILE = _("Remember this file(F)"),

	-- data variables
	readers = {},
	final_choice = nil,
	last_item = 0,
	current_item = 1,
	-- state variables
	dialogdirty = true,
	markerdirty = false,
	optiondirty = true,
	remember_preference = false,
	remember_association = false,
}

function GetRegisteredReaders(ftype)
	local s = ";"
	local readers = {}
	for key,value in pairs(registry) do
		if string.find(value[2],s..ftype..s) then
			table.insert(readers,key)
		end
	end
	table.sort(readers, function(a,b) return registry[a][3]<registry[b][3] end)
	return readers
end

-- find the first reader registered with this file type
function ReaderChooser:getReaderByType(ftype)
	local readers = GetRegisteredReaders(ftype)
	if #readers >= 1 then
		return registry[readers[1]][1]
	else
		if FileChooser.filemanager_mode == FileChooser.UNRESTRICTED then
			return CREReader
		else
			return nil
		end
	end
end

function ReaderChooser:getReaderByName(filename)
	local ext = string.match(filename, ".+%.([^.]+)")
	local file_type = ext and ext:lower() or "txt"
	local readers = GetRegisteredReaders(file_type)
	if #readers > 1 then -- more than one reader are registered with this file type
		local file_settings = DocSettings:open(filename)
		local reader_association = file_settings:readSetting("reader_association")
		local reader_preferences = G_reader_settings:readSetting("reader_preferences")
		Debug("Reading saved association:", reader_association)
		if reader_association and reader_association ~= "N/A" then
			file_settings:close()
			return registry[reader_association][1]

		elseif reader_preferences and reader_association ~= "N/A" then
			default_reader = reader_preferences[file_type]
			if default_reader then
				return registry[default_reader][1]
			end
		end
		-- need to choose reader
		Screen:saveCurrentBB()
		local name = self:choose(readers)
		if name then
			if self.remember_preference then
				if not reader_preferences then
					reader_preferences = {}
				end
				reader_preferences[file_type] = name
				G_reader_settings:saveSetting("reader_preferences", reader_preferences)
				file_settings:delSetting("reader_association") --override reader association
			end
			if self.remember_association then
				Debug("Saving last reader:", name)
				file_settings:saveSetting("reader_association", name)
			end
			file_settings:close()
			Screen:restoreFromSavedBB()
			return registry[name][1]
		else
			file_settings:close()
			return nil
		end

	elseif #readers == 1 then
		return registry[readers[1]][1]
	else
		if FileChooser.filemanager_mode == FileChooser.UNRESTRICTED then
			return CREReader
		else
			return nil
		end
	end
end

function ReaderChooser:drawBox(xpos, ypos, w, h, bgcolor, bdcolor)
	-- draw dialog border
	local r = 6  -- round corners
	fb.bb:paintRect(xpos, ypos+r, w, h - r, bgcolor)
	blitbuffer.paintBorder(fb.bb, xpos, ypos, w, r, r, bdcolor, r)
	blitbuffer.paintBorder(fb.bb, xpos+2, ypos + 2, w - 4, r, r, bdcolor, r)
end

function ReaderChooser:drawTitle(text, xpos, ypos, w, font_face)
	-- draw title text
	renderUtf8Text(fb.bb, xpos+10, ypos+self.title_H, font_face, text, true, self.BGCOLOR/15, 1.0)
	-- draw title bar
	fb.bb:paintRect(xpos, ypos+self.title_H+self.title_bar_H, w, 3, 5)

end

function ReaderChooser:drawReaderItem(name, xpos, ypos, font_face)
	-- draw reader name
	renderUtf8Text(fb.bb, xpos+self.margin_I, ypos, font_face, name, true, self.BGCOLOR/15, 1.0)
	return sizeUtf8Text(0, G_width, font_face, name, true).x
end

function ReaderChooser:drawOptions(xpos, ypos, barcolor, bgcolor, font_face)
	local width, height = self.WIDTH, self.HEIGHT
	local optbar_T = self.options_bar_T
	-- draw option border
	fb.bb:paintRect(xpos, ypos, width, optbar_T, barcolor)
	fb.bb:paintRect(xpos+(width-optbar_T)/2, ypos, optbar_T, self.options_H, barcolor)
	-- draw option cell
    local left_cell_bcolor = bgcolor+3*(self.remember_preference and 1 or 0)
    local right_cell_bcolor = bgcolor+3*(self.remember_association and 1 or 0)
	fb.bb:paintRect(xpos, ypos+optbar_T, (width-optbar_T)/2, self.options_H-optbar_T, left_cell_bcolor)
	fb.bb:paintRect(xpos+(width+optbar_T)/2, ypos+optbar_T, (width-optbar_T)/2, self.options_H-optbar_T, right_cell_bcolor)
	-- draw option text
	renderUtf8Text(fb.bb, xpos+self.margin_O, ypos+self.options_H/2+8, font_face, self.OPTION_TYPE, true, left_cell_bcolor/15, 1.0)
	renderUtf8Text(fb.bb, xpos+width/2+self.margin_O, ypos+self.options_H/2+8, font_face, self.OPTION_FILE, true, right_cell_bcolor/15, 1.0)
	fb:refresh(1, xpos, ypos, width, self.options_H-optbar_T)
end

function ReaderChooser:choose(readers)
	self.readers = {}
	self.final_choice = nil
	self.readers = readers
	self.dialogdirty = true
	self.markerdirty = false
	self.optiondirty = true
	self:addAllCommands()

	local tface = Font:getFace("tfont", self.title_font_size)
	local cface = Font:getFace("cfont", self.item_font_size)
	local fface = Font:getFace("ffont", self.option_font_size)

	local width, height = self.WIDTH, self.HEIGHT
	local topleft_x, topleft_y = (fb.bb:getWidth()-width)/2, (fb.bb:getHeight()-height)/2
	local botleft_x, botleft_y = topleft_x, topleft_y+height

	Debug("Drawing box")
	self:drawBox(topleft_x, topleft_y, width, height, self.BGCOLOR, 3)
	Debug("Drawing title")
	self:drawTitle(self.TITLE, topleft_x, topleft_y, width, tface)

	local reader_text_width = {}
	for index,name in ipairs(self.readers) do
		Debug("Drawing reader:",index,name)
		reader_text_width[index] = self:drawReaderItem(name, topleft_x, topleft_y+self.title_H+self.spacing*index+10, cface)
	end

	fb:refresh(1, topleft_x, topleft_y, width, height)

	-- paint first reader marker
	local xmarker = topleft_x + self.margin_I
	local ymarker = topleft_y + self.title_H + self.title_bar_H
	fb.bb:paintRect(xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3, 15)
	fb:refresh(1, xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3)

	local ev, keydef, command, ret_code
	while true do
		if self.markerdirty then
			fb.bb:paintRect(xmarker, ymarker+self.spacing*self.last_item, reader_text_width[self.last_item], 3, 3)
			fb:refresh(1, xmarker, ymarker+self.spacing*self.last_item, reader_text_width[self.last_item], 3)
			fb.bb:paintRect(xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3, 15)
			fb:refresh(1, xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3)
			self.markerdirty = false
		end

		if self.optiondirty then
			self:drawOptions(botleft_x, botleft_y-self.options_H, 5, 3, fface)
			self.optiondirty = false
		end

		ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			keydef = Keydef:new(ev.code, getKeyModifier())
			Debug("key pressed: "..tostring(keydef))
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				Debug("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				Debug("command not found: "..tostring(command))
			end
			if ret_code == "break" then
				ret_code = nil
				if self.final_choice then
					return self.readers[self.final_choice]
				else
					return nil
				end
			end
		end -- if
	end -- while
end

-- add available commands
function ReaderChooser:addAllCommands()
	self.commands = Commands:new{}
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		_("next item"),
		function(self)
			self.last_item = self.current_item
			self.current_item = (self.current_item + #self.readers + 1)%#self.readers
			if self.current_item == 0 then
				self.current_item = self.current_item + #self.readers
			end
			Debug("Last item:", self.last_item, "Current item:", self.current_item, "N items:", #self.readers)
			self.markerdirty = true
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		_("previous item"),
		function(self)
			self.last_item = self.current_item
			self.current_item = (self.current_item + #self.readers - 1)%#self.readers
			if self.current_item == 0 then
				self.current_item = self.current_item + #self.readers
			end
			Debug("Last item:", self.last_item, "Current item:", self.current_item, "N items:", #self.readers)
			self.markerdirty = true
		end
	)

	self.commands:add(KEY_T, nil, "T",
		_("remember reader choice for this type"),
		function(self)
			self.remember_preference = not self.remember_preference
			self.optiondirty = true
		end
	)

	self.commands:add(KEY_F, nil, "F",
		_("remember reader choice for this file"),
		function(self)
			self.remember_association = not self.remember_association
			self.optiondirty = true
		end
	)

	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		_("choose reader"),
		function(self)
			self.final_choice = self.current_item
			return "break"
		end
	)
	self.commands:add(KEY_BACK, nil, "Back",
		_("back"),
		function(self)
			return "break"
		end
	)
end
