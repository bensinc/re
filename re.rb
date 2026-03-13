require 'io/console'


$debug = true

class Editor
  attr_accessor :mode, :repeat_count, :status_message, :command, :operator

  def initialize
    @mode = :normal
    @repeat_count = ""
    @status_message = ""
    @command = ""
    @operator = nil
  end

  def repeater(&block)
    [(@repeat_count.to_i), 1].max.times { block.call }
    @repeat_count = ""
  end
end

def log(s)
  if $debug
    @log = File.open("log.txt", "w")
    @log.puts s 
    @log.close
  end
end


$rows, $cols = $stdout.winsize


log("Starting -- Window size: #{$cols}, #{$rows}")

file = ""

Signal.trap("SIGWINCH") do
  $rows, $cols = $stdout.winsize
  display
end

class Display
  def clear_screen
    print "\e[2J"   # clear entire screen
    print "\e[H"    # move cursor to top left
  end

  def move_to(x, y)
    print "\e[#{y};#{x}H"
  end

  def write_at(x, y, text)
    move_to(x, y)
    print text
  end

  def move_cursor(x, y)
    print "\e[#{y};#{x}H"
  end
end

class Buffer
  attr_accessor :data

  def initialize(file = nil)
    @data = []
    if file
      @path = file
      File.readlines(file, chomp: false).each do |line|
        @data << line
      end

    end
  end

  def insert(x, y, c)
    if c == "\n"
      log("Insert newline")
      if x == 0
        @data.insert(y, "\n")
      else
        parts = [@data[y][0..x], @data[y][x..-1]]

        log(parts)
      
        @data.insert(y+1, parts[1])
        @data[y] = parts[0]
      end
    else
      @data[y].insert(x, c)
    end
  end
  
  def remove(x, y)
    @data[y].slice!(x)
    @data.delete_at(y) if @data[y] == ""
  end
  
  def replace_char(x, y, c)
    @data[y][x] = c
  end

  
  def remove_line(y)
    @data.delete_at(y)
  end
  
  def save
    f = File.open(@path, "w")
    @data.each do |line|
      f.puts line
    end
    f.close
    return true
  end
end

class Cursor

  attr_accessor :x, :y

  def initialize(x = 0, y = 0)
    @x = x
    @y = y
  end

  def move(direction)
    case direction
    when :up
      @y -= 1
    when :down
      @y += 1
    when :left
      @x -= 1
    when :right
      @x += 1
    when :first
      @x = 0
    when :home
      @x = 0
      @y = 0
    end
  end
  
  def set_mode(mode)
    print "\e[6 q"   if mode == :pipe
    print "\e[2 q"   if mode == :block
  end
end

class BufferDisplay
  attr_accessor :cursor

  def initialize(display, buffer, editor)
    @display = display
    @buffer = buffer
    @editor = editor
    @cursor = Cursor.new
    @size = [$cols, $rows - 2]
    @position = [0, 2]
    @top_row = 0
    @gutter_width = @buffer.data.length.to_s.length + 1
    @screen_map = []
  end

  def content_width
    @size[0] - @gutter_width - 2
  end

  def visible_rows
    @size[1] - 2
  end

  def build_screen_map
    @gutter_width = @buffer.data.length.to_s.length + 1
    @screen_map = []

    @buffer.data.each_with_index do |line, buf_y|
      chunks = line.chomp.chars.each_slice(content_width).map(&:join)
      chunks = [""] if chunks.empty?

      chunks.each_with_index do |chunk, sub_idx|
        @screen_map << { buffer_line: buf_y, sub_line: sub_idx, text: chunk }
      end
    end
  end

  def screen_row_for(buf_x, buf_y)
    row = 0
    @buffer.data[0...buf_y].each do |line|
      row += [(line.chomp.length.to_f / content_width).ceil, 1].max
    end
    row += buf_x / content_width
    row
  end

  def insert(c)
    @buffer.insert(@cursor.x, @cursor.y, c)
    if c == "\n"
      @cursor.move(:down)
      @cursor.move(:first)
    else
      @cursor.move(:right)
    end
  end

  def backspace
    @buffer.remove(@cursor.x, @cursor.y)
    cursor.move(:left)
  end

  def remove_char
    @buffer.remove(@cursor.x, @cursor.y)
  end

  def replace_char(c)
    @buffer.replace_char(@cursor.x, @cursor.y, c)
  end

  def remove_line
    @buffer.remove_line(@cursor.y)
  end

  def move_cursor_to_end
    @cursor.x = @buffer.data[@cursor.y].chomp.length
  end

  def render
    @size = [$cols, $rows - 2]
    build_screen_map

    # Clamp cursor before computing screen position
    clamp_cursor

    # Scroll to keep cursor visible
    cursor_screen_row = screen_row_for(@cursor.x, @cursor.y)
    if cursor_screen_row >= @top_row + visible_rows
      @top_row = cursor_screen_row - visible_rows + 1
    end
    if cursor_screen_row < @top_row
      @top_row = cursor_screen_row
    end

    # Draw visible rows
    visible = @screen_map[@top_row, visible_rows] || []
    visible.each_with_index do |entry, i|
      screen_y = @position[1] + 1 + i
      if entry[:sub_line] == 0
        gutter = (entry[:buffer_line] + 1).to_s.rjust(@gutter_width)
      else
        gutter = " " * @gutter_width
      end
      @display.write_at(1, screen_y, "\e[2m#{gutter}\e[0m #{entry[:text]}")
    end

    move_cursor
  end

  def clamp_cursor
    @cursor.y = @cursor.y.clamp(0, [@buffer.data.length - 1, 0].max)
    line_len = (@buffer.data[@cursor.y] || "\n").chomp.length
    max_x = [line_len - 1, 0].max
    max_x = line_len if @editor.mode == :insert
    @cursor.x = @cursor.x.clamp(0, max_x)
  end

  def move_cursor
    clamp_cursor

    cursor_screen_row = screen_row_for(@cursor.x, @cursor.y) - @top_row
    screen_col = (@cursor.x % content_width) + @gutter_width + 2

    @display.move_cursor(screen_col, @position[1] + 1 + cursor_screen_row)
  end

  def set_mode(mode)
    @editor.mode = mode
    @cursor.set_mode(@editor.mode == :insert ? :pipe : :block)
  end

  def save(filename = nil)
    if @buffer.save
      @editor.status_message = "Saved!"
    else
      @editor.status_message = "Error saving!"
    end
  end

end

@display = Display.new
@editor = Editor.new
@buffer = Buffer.new("test.txt")
@buffer_display = BufferDisplay.new(@display, @buffer, @editor)

def display
  @display.clear_screen
  @display.write_at(1, 1, "[re editor] [#{@buffer_display.cursor.x}, #{@buffer_display.cursor.y}] #{@editor.status_message}")
  @display.write_at(1, 2, "─" * $cols)

  if @editor.mode == :command
    modeline = "[command: #{@editor.command}]"
  else
    modeline = "[#{@editor.mode}]─"
  end

  modeline << "(#{@editor.repeat_count})─" if @editor.repeat_count != ""
  modeline += "─" * ($cols - modeline.length)

  @display.write_at(1, $rows, modeline)

  @buffer_display.render
end

def read_key
  $stdin.noecho do |io|
    io.raw do
      input = io.readpartial(4)
      case input
      when "\e[A"     then :up
      when "\e[B"     then :down
      when "\e[C"     then :right
      when "\e[D"     then :left
      when "\r", "\n" then :enter
      when "\e"       then :escape
      when "\u0003"   then :ctrl_c
      when "\u007F"   then :backspace
      when "\u0013"   then :ctrl_s
      else input
      end
    end
  end
end

def execute_command
  case @editor.command
  when "w"
    @buffer_display.save
  when "q"
    exit
  end
end

def execute_operator(operator, motion)
  case operator
  when "d"
    case motion
    when "d"
      @editor.repeater { @buffer_display.remove_line }
    end
  end
end

def handle_key(key)
  # Arrows work in every mode
  if [:left, :right, :up, :down].include?(key)
    @buffer_display.cursor.move(key)
    return
  end

  case @editor.mode
  when :replace
    if key.is_a?(String) && key.length == 1 && key.match?(/[[:print:]]/)
      @buffer_display.replace_char(key)
    end
    @editor.mode = :normal

  when :operator_pending
    execute_operator(@editor.operator, key)
    @editor.operator = nil
    @editor.mode = :normal

  when :command
    case key
    when :escape
      @editor.mode = :normal
    when :enter
      execute_command
      @editor.mode = :normal
    when :backspace
      @editor.command.chop!
    else
      @editor.command << key if key.is_a?(String) && key.length == 1 && key.match?(/[[:print:]]/)
    end

  when :normal
    case key
    when ":"
      @editor.mode = :command
      @editor.command = ""
    when :ctrl_s
      @buffer_display.save
    when "i"
      @buffer_display.set_mode(:insert)
    when "a"
      @buffer_display.cursor.move(:right)
      @buffer_display.set_mode(:insert)
    when "A"
      @buffer_display.move_cursor_to_end
      @buffer_display.set_mode(:insert)
    when "0".."9"
      @editor.repeat_count = "#{@editor.repeat_count}#{key}"
      @editor.repeat_count = "" if @editor.repeat_count == "0"
    when :escape
      @editor.repeat_count = ""
    when "x"
      @editor.repeater { @buffer_display.remove_char }
    when "d"
      @editor.operator = "d"
      @editor.mode = :operator_pending
    when "r"
      @editor.mode = :replace
    end

  when :insert
    case key
    when :enter
      @buffer_display.insert("\n")
    when :backspace
      @buffer_display.backspace
    when :escape
      @buffer_display.set_mode(:normal)
    else
      @buffer_display.insert(key)
    end
  end
end

loop do
  display
  key = read_key
  break if key == :ctrl_c
  handle_key(key)
end
