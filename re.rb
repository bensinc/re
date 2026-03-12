require 'io/console'


rows, cols = $stdout.winsize

file = ""

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
      File.readlines(file, chomp: false).each do |line|
        @data << line
      end

    end
  end
end

class Cursor

  attr_accessor :x
  attr_accessor :y

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
    end
  end
end

class BufferDisplay
  attr_accessor :cursor
  def initialize(display, buffer)
    @display = display
    @buffer = buffer
    @cursor = Cursor.new
    @size = [30, 10]
    @position = [5, 5]
  end

  def insert(c)
    @buffer.data[@cursor.y].insert(@cursor.x, c)
    @cursor.move(:right)
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
     draw_box(@position[0], @position[1], @size[0], @size[1]) 
     start_x = 1
     start_y = 1
     x = @position[0] + start_x
     y = @position[1] + start_y
     @buffer.data.each do |line|
       line.chars.each_slice(@size[0]-2).map(&:join).each do |wrapped_line|
         @display.write_at(x, y, wrapped_line)
         y += 1
        end
     end
     move_cursor
  end

  def move_cursor
    @display.move_cursor(@position[0] + @cursor.x + 1, @position[1] + @cursor.y + 1)
  end

end

@display = Display.new

@buffer = Buffer.new("test.txt")

@buffer_display = BufferDisplay.new(@display, @buffer)




def display
  @display.clear_screen
  @display.write_at(1, 1, "[re editor] [#{@buffer_display.cursor.x}, #{@buffer_display.cursor.y}]")
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
      else input
      end
    end
  end
end

loop do
  display
  key = read_key
  # puts "Got: #{key.inspect}"
  break if key == :ctrl_c

  case key
  when :left, :right, :up, :down
    @buffer_display.cursor.move(key)
  else
    @buffer_display.insert(key) 
  end
  display



end
