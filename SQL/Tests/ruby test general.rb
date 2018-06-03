require 'pg'

Conn = PG.connect( :dbname => "kmar", :user => "kmar", :password => "replace me with your db password")

room = 0
count = 2

result = Conn.exec(
"SELECT * FROM \"USERNAMES\" INNER JOIN
(SELECT MAX(\"LAST_USED\"), \"USER_ID\" FROM \"USERNAMES\" GROUP BY \"USER_ID\") AS \"GROUPEDUSERNAMES\"
ON ( \"LAST_USED\" = \"LAST_USED\" AND \"USER_ID\" = \"USER_ID\");"
 )

result.each do |message|
	puts "#{message["TIME"]} #{message["USERNAME"]}: #{message["TEXT"]}"
end
