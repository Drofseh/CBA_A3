module Cba
class Generator
	USAGE = "USAGE: ruby #{File.basename(__FILE__)} PATH"
	OUTPUT = 'CfgFunctions.hpp'

	TEST_FILE = 'test.sqf'
	TEST_PATTERN = /^test_(.*).sqf$/

	DOC_PROJECT = 'ndocs-project'

	DOC_MENU = "#{DOC_PROJECT}/Menu.txt"
	DOC_MENU_TEMPLATE = "#{DOC_PROJECT}/menu_template.txt"

	DOC_LANGUAGE = "#{DOC_PROJECT}/Languages.txt"
	DOC_LANGUAGE_TEMPLATE = "#{DOC_PROJECT}/languages_template.txt"

	TEMPLATE_HEADER =<<END_TEXT
# -----------------------------------------------------------------------------
# Automatically generated by '#{File.basename($0)}'
# DO NOT MANUALLY EDIT THIS FILE!
# -----------------------------------------------------------------------------
END_TEXT

	SQF_HEADER = TEMPLATE_HEADER.gsub(/^#/, '//')
	CFG_HEADER = SQF_HEADER

	# Generate all files.
	protected
	def initialize(path, relative_path)
		tests path, relative_path

		all_configs = function_declarations path, relative_path

		docs path, all_configs
	end

	# Create a test for a single addon folder.
	protected
	def folder_test(path, relative_path)

		type = File.basename(path)
		# Get list of tests in folder before creating a test file.
		tests = Array.new
		Dir.new(path).each do |file|
			if file =~ TEST_PATTERN
				tests.push $1
			end
		end

		# Create a test file which will test all the functions in the addon.
		unless tests.empty?
			File.open(File.join(path, TEST_FILE), 'w') do |file|
				file.puts <<END_SQF
#{SQF_HEADER}
#include "script_component.hpp"

#define TESTS [#{tests.collect { |s| "\"#{s}\"" }.join(', ')}]

SCRIPT(test-#{type});

// ----------------------------------------------------------------------------

LOG("=== Testing #{type.capitalize} ===");

{
	call compile preprocessFileLineNumbers format ["#{relative_path.gsub('/','\\')}\\#{type.downcase}\\test_%1.sqf", _x];
} forEach TESTS;

nil;
END_SQF
			end
		end

		return (not tests.empty?)
	end

	# Create tests for all addon folders.
	protected
	def tests(path, relative_path)
		# Get list of testable categories in folder before creating a test file.
		categories = Array.new
		Dir.new(path).each do |file|
			full_path = File.join(path, file)
			# Generate all files.
			if file != '..' and file != '.' and File.directory? full_path
				categories.push file if folder_test(full_path, relative_path)
			end
		end

		File.open(File.join(path, 'main', TEST_FILE), 'w') do |file|
			file.puts <<END_SQF
#{SQF_HEADER}
#include "script_component.hpp"

#define CATEGORIES [#{categories.collect { |s| "\"#{s}\"" }.join(', ')}]

SCRIPT(test);

// ----------------------------------------------------------------------------

LOG("===--- Testing ---===");

{
	call compile preprocessFileLineNumbers format ["#{relative_path.gsub('/','\\')}\\%1\\#{TEST_FILE}", _x];
} forEach CATEGORIES;

nil;
END_SQF
		end
	end

	protected
	def function_declarations(path, relative_path)

		all_configs = Hash.new

		addon_paths = Dir.glob(File.join(path,"*")).select { |fn| File.directory?(fn) }.sort
		addon_paths.each do |addon_path|
			addon = File.basename(addon_path)

			if addon_path =~ %r[^#{path}/(?:\w+_)?([^/\.]+)$]

				type = $1
				type = 'misc' if type =~ /^common$/i

				puts "\n=> #{addon_path}"
				config = Hash.new

				function_files = Dir.glob(File.join(addon_path, "*.sqf")).sort { |a,b| File.basename(a)<=>File.basename(b) }
				function_files.each do |function_file|
				  function_file = File.basename(function_file)

					if function_file =~ /^fnc_(\w+)\.sqf$/i
						name = $1

						type.capitalize!
						source = File.read(File.join(addon_path, function_file))

						unless source =~ /^\s*Function:\s*(\w+)_fnc_#{name}/i
							$stderr.puts ">>> ERROR >>> Incorrect/missing Function name documented in: #{function_file} (not adding to fns module)"
							#exit false
							next
						end

						tag = $1

						description = if source =~ /Description:\s*([^\b]*?)\n\s*\n/
							$1.gsub(/\s*\n\s*/, ' ')
						else
							'<NO DESC>'
						end

						puts "Adding #{function_file}: #{description}"

						config[tag] = Hash.new unless config[tag]
						config[tag][type] = Hash.new unless config[tag][type]
						config[tag][type][name] = {
							:description => description,
							:path => "#{relative_path.gsub(/\//, '\\')}\\#{addon}\\#{function_file}",
							:name => "#{tag}_fnc_#{name}"
						}
					end
				end

				unless config.empty?
					output_file = File.join(addon_path, OUTPUT)

					# CfgFunctions >> Tag >> function type >> function.
					File.open(output_file, 'w') do |file|
						file.puts <<END_CONFIG
#{CFG_HEADER}
class CfgFunctions
{
END_CONFIG
						config.each_pair do |tag, types|
							file.puts "\tclass #{tag}\n\t{";

							types.each_pair do |type, functions|
								file.puts "\t\tclass #{type}\n\t\t{";

								functions.each do |function, data|
									file.puts <<END_CONFIG
			// #{data[:name]}
			class #{function}
			{
				description = "#{data[:description].gsub(/"/, '""')}";
				file = "#{data[:path]}";
			};
END_CONFIG
								end

								file.puts "\t\t};";
							end

							file.puts "\t};";
						end
						# Add the missing BIS functions to the CfgFunctions.hpp
						# in CBA common
						if type == 'Misc'
							file.puts <<END_BISFIX
	// Missing BIS functions
	class BIS {
		class variables {
			class undefCheck {
				file = "\\x\\cba\\addons\\common\\dummy.sqf";
			};
		};
	};
	class BIS_PMC {
		class PMC_Campaign {
			class initIdentity {
				file = "\\x\\cba\\addons\\common\\dummy.sqf";
			};
		};
	};
END_BISFIX
						end
						file.puts "};";
					end
				end

				config.each_pair do |tag, types|
					all_configs[tag] = Hash.new if all_configs[tag].nil?
					types.each_pair do |type, functions|
						all_configs[tag][type] = Hash.new if all_configs[tag][type].nil?
						all_configs[tag][type].merge! functions
					end
				end
			end
		end

		all_configs
	end

	# Generate a menu for Ndocs.
	protected
	def docs(path, all_configs)

		menu_template = File.read(DOC_MENU_TEMPLATE)
		menu = ''

		all_configs.to_a.sort { |a, b| a[0] <=> b[0] }.each do |tag, types|
			menu += "\tGroup: #{tag} {\n"
			types.to_a.sort { |a, b| a[0] <=> b[0] }.each do |type, functions|
				menu += "\t\tGroup: #{type} {\n"
				functions.to_a.sort { |a, b| a[0] <=> b[0] }.each do |function, data|
					data[:path] =~ /\\Addons\\(.*)$/i
					folder = $1
					data[:name] =~ /_fnc_(.*)$/
					name = $1
					menu += "\t\t\tFile: #{name}  (no auto-title, #{folder})\n"
				end
				menu += "\t\t} # Group: #{type}\n\n"
			end
			menu += "\t} # Group: #{tag}\n\n"
		end
		menu_template.sub!(/\$FUNCTIONS\$/, menu)

		File.open(DOC_MENU, 'w') do |file|
			file.puts TEMPLATE_HEADER
			file.puts menu_template
		end
		puts "\nGenerated #{DOC_MENU}"

		# Generate a language template file for NDocs.
		language_template = File.read(DOC_LANGUAGE_TEMPLATE)
		language_template.sub!(/\$IGNORED_PREFIXES\$/, all_configs.keys.collect { |s| "#{s}_fnc_"}.join(' '))
		File.open(DOC_LANGUAGE, 'w') do |file|
			file.puts TEMPLATE_HEADER
			file.puts language_template
		end
		puts "\nGenerated #{DOC_LANGUAGE}"
	end
  end
end

if __FILE__ == $0

	unless ARGV.size == 1
		puts "Generate function declarations for Functions module."
		puts Cba::Generator::USAGE
		exit
	end

	path = File.expand_path(ARGV[0])

	unless File.directory? path
		puts "Could not find directory: #{path}"
		puts File.cwd
		puts Cba::Generator::USAGE
		exit
	end

	path =~ %r[(/x/.*)$]
	relative_path = $1

	unless relative_path
		puts "Could not find relative directory in: #{path}"
		puts Cba::Generator::USAGE
		exit
	end

	Cba::Generator.new(path, relative_path)
end

