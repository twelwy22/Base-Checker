Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

if Gem.win_platform?
  require 'io/console'
  STDOUT.set_encoding(Encoding::UTF_8)
end

require 'json'
require 'colorize'
require 'csv'
require 'roo'
require 'logger'
require 'fileutils'
require 'concurrent'

def save_results_to_json(results, query)
  results = results.map do |file, data|
    [file, data.encode('UTF-8', 'IBM866', invalid: :replace, undef: :replace, replace: '')]
  end

  File.open("result/results_#{query}.json", 'w:UTF-8') do |file|
    file.write(JSON.pretty_generate(results))
  end
  puts "Результаты сохранены в файл: result/results_#{query}.json"
end




LOGGER = Logger.new(STDOUT)
LOGGER.level = Logger::INFO

$files_folder = File.join(File.dirname(File.expand_path(__FILE__)), 'data')
$files_to_load = Dir.entries($files_folder).select { |f| f.match?(/\.txt$|\.csv$|\.xlsx$/) }


$user_last_message_time = {}
$flood_timeout = 5 

def search_in_file(file_path, file, query)
  results = []
  begin
    case File.extname(file)
    when '.txt'
      File.open(file_path, 'rb') do |f|
        f.each_line do |line|
          results << [file, line.strip] if line.force_encoding('UTF-8').include?(query)
        end
      end
    when '.csv'
      CSV.foreach(file_path, headers: false, encoding: 'utf-8') do |row|
        results << [file, row] if row.any? { |cell| cell.to_s.include?(query) }
      end
    when '.xlsx'
      workbook = Roo::Excelx.new(file_path)
      workbook.each_row_streaming do |row|
        results << [file, row.map(&:value)] if row.any? { |cell| cell.value.to_s.include?(query) }
      end
    end
  rescue => e
    LOGGER.error("Ошибка при обработке файла #{file}: #{e.message}")
  end
  results
end

def is_user_flooding(user_id)
  now = Time.now
  last_message_time = $user_last_message_time[user_id] || (now - $flood_timeout - 1)
  
  if now - last_message_time < $flood_timeout
    true
  else
    $user_last_message_time[user_id] = now
    false
  end
end


def search_in_files(query)
  results = []

  futures = $files_to_load.map do |file|
    Thread.new do
      file_path = File.join($files_folder, file)
      puts "Проверяю базу данных: #{file}..."
      search_in_file(file_path, file, query)
    end
  end

  futures.each do |thread|
    result = thread.value
    if result.any?
      puts "Найденные данные: #{result}"
      results.concat(result)
    else
      puts "В базе данных ничего не найдено."
    end
  end

  save_results_to_json(results, query) if results.any?

  results
end


def print_results(results)
  puts "Найденная информация:\n".blue
  results.each do |file_name, result|
    puts "Название базы данных: #{file_name}".blue
    puts "└  #{result.join(', ')}".blue
  end
end

def main
  user_id = 'console_user'

  banner = <<~BANNER
    #{'██████╗  █████╗ ███████╗███████╗     ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗███████╗██████╗ '.blue}
    #{'██╔══██╗██╔══██╗██╔════╝██╔════╝    ██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝██╔════╝██╔══██'.blue}
    #{'██████╔╝███████║███████╗█████╗      ██║     ███████║█████╗  ██║     █████╔╝ █████╗  ██████╔╝'.blue}
    #{'█╔══██╗ ██╔══██║╚════██║██╔══╝      ██║     ██╔══██║██╔══╝  ██║     ██╔═██╗ ██╔══╝  ██╔══██'.blue}
    #{'██████╔╝██║  ██║███████║███████╗    ╚██████╗██║  ██║███████╗╚██████╗██║  ██╗███████╗██║  ██║'.blue}
    #{'                                Made by Yoshiko'.blue}
    #{'github.com/twelwy22'.red.bold}
    #{'Free - base checker'.green.bold}
  BANNER
  puts banner

  loop do
    print 'Введите запрос для поиска: '.blue.bold
    query = gets.strip

    if is_user_flooding(user_id)
      puts 'Пожалуйста, подождите немного перед тем, как отправлять следующий запрос.'.red
      next
    end

    results = search_in_files(query)
    puts 'Ничего не найдено.'.yellow if results.empty?
  end
end

main if __FILE__ == $PROGRAM_NAME
