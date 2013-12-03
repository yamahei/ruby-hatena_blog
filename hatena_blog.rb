#!/usr/bin/ruby

require 'yaml'
require 'cgi'
require 'time'

#Module: Selenium::WebDriver::SearchContext — Documentation by YARD 0.8.1
#http://selenium.googlecode.com/svn/trunk/docs/api/rb/frames.html
require "selenium-webdriver"

class HatenaBlog

	attr_accessor :browser, :socialize
	MAX = 3600

	def initialize(config)
		File.open(config){ | file |
			yaml = YAML.load(file.read())
			@HatenaID = yaml["HatenaID"]
			@BlogDomain = yaml["BlogDomain"]
			@Password = yaml["Password"]
			@browser = :firefox
			@socialize = true
		}
	end
	
	def webdriver

		# init web driver
		driver = Selenium::WebDriver.for @browser
		# login
		driver.navigate.to loginurl
		driver.find_element(:xpath, "//input[@name='name']").send_keys @HatenaID
		driver.find_element(:xpath, "//input[@name='password']").send_keys @Password
		check = driver.find_element(:xpath, "//input[@name='persistent']")
		check.click if check.attribute("checked") =~ /^true$/i
		driver.find_element(:xpath, "//form[@action='/login']").submit
		# wait until redirect
		MAX.times do
			url = driver.current_url
			break if url == summaryurl
			sleep 1
		end
		
	
		# get draft list
		draftinfos = []
		driver.navigate.to draftsurl

		form = driver.find_element(:xpath, "//form[@id='delete-form']/table[@class='table']")
		drafts = form.find_elements(:xpath, "//tr[@data-uuid]")
		drafts.each{| tr |
			draftinfo = {}
			draftinfo[:uuid] = tr.attribute("data-uuid")
			draftinfo[:title] = tr.find_element(:class_name, "draft-title").text.strip
			draftinfo[:button] = tr.find_element(:class_name, "btn")
			draftinfos << draftinfo
		}
	
		# do caller proc
		yield(driver, draftinfos)

		# logout
		driver.navigate.to "http://www.hatena.ne.jp/logout"
		sleep 1
		driver.close
		
	end

	def loginurl
		location = "http://blog.hatena.ne.jp/#{@HatenaID}/#{@BlogDomain}/"
		"https://www.hatena.ne.jp/login?location=#{CGI.escape(location)}"
	end

	def summaryurl
		"http://blog.hatena.ne.jp/#{@HatenaID}/#{@BlogDomain}/"
	end

	def draftsurl
		summaryurl + "drafts"
	end

	
	def get_draft_infos#=>[{:title, :uuid, :button}]
		draftinfos = []
		webdriver { | browser, infos |
			infos.each{ | info | 
				draftinfos.push({:uuid=>info[:uuid], :title=>info[:title]})
			}
		}
		return draftinfos
	end

	def publish_draft(uuid)
		webdriver { | browser, infos |
			info = infos.find{ | item | item[:uuid] == uuid }
			raise "Error: uuid(#{uuid}) not found." if !info

			info[:button].click
			MAX.times do
				url = browser.current_url
				break if url =~ /edit\?entry=#{uuid}/
				sleep 1
			end

			browser.find_element(:xpath, "//form[@id='edit-form']").submit

			if @socialize then
				wait = Selenium::WebDriver::Wait.new(:timeout => 10) # seconds
				wait.until { browser.find_element(:xpath, "//form[@id='socialize-form']") }
				browser.find_element(:xpath, "//form[@id='socialize-form']").submit
			end
			
			#TODO: self bookmark?
		}
	end

end


if __FILE__ == $0

	begin
		config, command = ARGV.shift, ARGV.shift
		raise "Config not found." if !File.exist?(config)
		case command.downcase
		when "list"
			(HatenaBlog.new(config)).get_draft_infos.each{ |draft|
				puts "#{draft[:uuid]}\t#{draft[:title]}"
			}
		when "post"
			uuid, date = ARGV.shift, Time.parse(ARGV.join(" "))
			raise "The past datetime." if date < Time.now
			sleep date - Time.now
			(HatenaBlog.new(config)).publish_draft(uuid)
		else
			raise "Don't you know?"
		end
	rescue => ex
		puts ex.message
		puts "USAGE:"
		puts "  #{__FILE__} CONFIG_FILE COMMAND [ARGUMENTS...]"
		puts "COMMAND:"
		puts "  LIST - Get list of Drafts."
		puts "  POST UUID YYYY/MM/DD-HH:MM:SS - Schedule to post a draft."
	end

end

