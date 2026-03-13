require 'io/console'


$debug = true

$mode = :normal

$repeat_count = ""

$status_message = ""

$last_key = nil 

$replace_mode = false

$command = ""

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

  def initialize(display, buffer)
    @display = display
    @buffer = buffer
    @cursor = Cursor.new
    @size = [$rows - 2, $cols]
    @position = [0, 2]
    @top_line = 0
    @gutter_width = @buffer.data.length.to_s.length + 1

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
    @cursor.x = @buffer.data[@cursor.y].length
  end

  def draw_box(x, y, width, height)
    # Corners
    @display.write_at(x,             y,              "┌")
    @display.write_at(x + width - 1, y,              "┐")
    @display.write_at(x,             y + height - 1, "└")
    @display.write_at(x + width - 1, y + height - 1, "┘")

    # Top and bottom edges
    (1...width - 1).each do |i|
      @display.write_at(x + i, y,              "─")
      @display.write_at(x + i, y + height - 1, "─")
    end

    # Left and right edges
    (1...height - 1).each do |j|
      @display.write_at(x,             y + j, "│")
      @display.write_at(x + width - 1, y + j, "│")
    end
  end

  def render
     # draw_box(@position[0], @position[1], @size[0], @size[1]) 
     start_x = 1
     start_y = 1
     x = @position[0] + start_x
     y = @position[1] + start_y
     
     @gutter_width = @buffer.data.length.to_s.length + 1
    
     log("Rendering buffer from #{@top_line} to #{@size[1] + @top_line}") 
     
     lines_rendered = 0 
     @buffer.data[@top_line..@top_line + @size[1]].each do |line|
       line.chars.each_slice(@size[0]-@gutter_width).map(&:join).each do |wrapped_line|
         # log("Writing: #{wrapped_line}")
         gutter = lines_rendered.to_s.rjust(@gutter_width)
         @display.write_at(x, y, "\e[2m#{gutter}\e[0m #{wrapped_line}")
         y += 1
         lines_rendered += 1
         if lines_rendered >= @size[1]-2
           # log "Breaking with #{lines_rendered}"
          end
        end
     end

     move_cursor
  end

  def move_cursor
    @cursor.x = 0 if @cursor.x < 0
    @cursor.y = 0 if @cursor.y < 0
    
    # log "Length: #{@buffer.data.length}"
    
    @cursor.y = @buffer.data.length - 1 if @cursor.y > @buffer.data.length - 1
    
    # log "Cursor line: #{@buffer.data[@cursor.y]} (#{@buffer.data[@cursor.y].length})"
    
    @cursor.x = @buffer.data[@cursor.y].length - 1 if @cursor.x > @buffer.data[@cursor.y].length - 1
    
    @display.move_cursor(@position[0] + @cursor.x + @gutter_width + 2, @position[1] + @cursor.y + 1)
  end
  
  def set_mode(mode)
    $mode = mode
    @cursor.set_mode($mode == :insert ? :pipe : :block)
  end
  
  def save(filename = nil)
    if @buffer.save
      $status_message = "Saved!"
    else
      $status_message = "Error saving!"
    end
    
    
  end

end

@display = Display.new

@buffer = Buffer.new("test.txt")

@buffer_display = BufferDisplay.new(@display, @buffer)




def display
  # log("Render")
  @display.clear_screen
  @display.write_at(1, 1, "[re editor] [#{@buffer_display.cursor.x}, #{@buffer_display.cursor.y}] #{$status_message}")
  @display.write_at(1, 2, "─" * $cols)
 
  if $mode == :command 
    modeline = "[command: #{$command}]"
  else
    modeline = "[#{$mode.to_s}]─"
  end
  
  modeline << "(#{$repeat_count})─" if $repeat_count != ""
  
  
  modeline += "─" * ($cols - modeline.length)
  
  @display.write_at(1, $rows, modeline)
  
  
  # $status_message = ""

  @buffer_display.render
end


def read_key
  $stdin.noecho do |io|
    io.raw do
      input = io.readpartial(4)  # read up to 4 bytes (arrows are 3-byte sequences)
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

def repeater(&block)
  [($repeat_count.to_i), 1].max.times { block.call }
  $repeat_count = ""
end

def execute_command
  case $command
  when "w"
    @buffer_display.save
  when "q"
    exit
  end
end

loop do
  display
  key = read_key
  # puts "Got: #{key.inspect}"
  break if key == :ctrl_c
 
  if $replace_mode
    if key.is_a?(String) && key.length == 1 && key.match?(/[[:print:]]/)
     @buffer_display.replace_char(key)
    end
   $replace_mode = false
  elsif $mode == :command
    case key
    when :escape
      $mode = :normal
    when :enter
      execute_command
      $mode = :normal
    when :backspace
      $command.chop!
    else
      $command << key if key.is_a?(String) && key.length == 1 && key.match?(/[[:print:]]/)
    end
  elsif $mode == :normal
    case key
    when :left, :right, :up, :down
      @buffer_display.cursor.move(key)
    when ":"
      $mode = :command
      $command = ""
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
      $repeat_count = "#{$repeat_count}#{key}"
      $repeat_count = "" if $repeat_count == "0"
    when :escape
      $repeat_count = ""
    when "x"
      repeater { @buffer_display.remove_char }
    when "d"
      if $last_key == "d"
        repeater { @buffer_display.remove_line }
        $last_key = nil
      else
        $last_key = "d"
      end
    when "r"
      $replace_mode = true
    else
      
    end
  elsif $mode == :insert
    case key
    when :left, :right, :up, :down
      @buffer_display.cursor.move(key)
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
  
  
  display



end
