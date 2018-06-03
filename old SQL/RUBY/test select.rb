require 'dbi'
#require_relative 'OCI8'

dbimethods = (DBI.methods - Object.methods).sort

dbimethods.each do |text|
	puts text
end

puts
puts "Drivers: "
DBI.available_drivers.each do |driver|
	puts drive
end
	



dbh = DBI.connect('oci8', 'sa', 'sa')

rs = dbh.prepare("SELECT * FROM RIGHTS")
rs.excecute
while rsrow = rs.fetch do
	puts rsrow
end
rs.finish
dbh.disconnect
