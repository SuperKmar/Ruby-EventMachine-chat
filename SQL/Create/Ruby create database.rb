require "pg"

def connect
	conn = PG.connect( :dbname => "kmar", :user => "kmar", :password => "C@n1sM@j0r1s")
end

def exec_sql conn, text
	conn.exec(text)
end

puts conn = connect


files = Dir[__FILE__+"*.txt"] #should list all the sql files in this dir
files.sort.each do |filename|
#filename = "rights created and edited.txt"
	puts file = File.expand_path("../../Create/" + filename, __FILE__) 
	puts "=========SQL TEXT========="
	lines = IO.readlines(file)
	lines.each do |line|
		puts line
	end
	puts "--------------------------"
	puts 
	exec_sql conn, lines.join("")
end
