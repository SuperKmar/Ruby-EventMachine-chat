require 'eventmachine'
require 'em-websocket'
require 'digest'
require 'json'
require "pg"

class Chatconnection < EventMachine::WebSocket::Connection
	#self:
	# name, name ID (current name in use)
	# user (user ID)
	# rights
	# current room (room ID)
	
	attr_accessor :name, :name_ID, :user_ID, :user_rights, :room_ID
	def initialize( opts = {} )
		super
		onopen { on_open }
		onmessage { |message| on_message(message) }
		onclose { on_close }
	end

	def on_open
	end

	def on_message(message)
		command = message[0] == "!"
		if command
			command, *params = message.split(" ")
			case command
				########################login###########################
				when "!login" #login if found in DB			
			
					if params.size < 1 or params.size > 2
						send_error "incorrect paramaters given. Type !help for more info on commands and their use"
					else
						if name
							send_error "you are already logged in as #{name}"
						else
							result = login params[0], params[1] || ""
							if result 
								self.name =  params[0]
								Chat.add_connection self
								loadrooms
							else
								send_error "username or password not correct - please try again"
							end
						end
					end
				########################register########################
				when "!register" #add to DB if username is not taken			
					if params.size < 1 or params.size > 2
						send_error "incorrect paramaters given. Type !help for more info on commands and their use"
					else
						result = register params[0], params[1] || ""
						if result
							self.name =  params[0]
							Chat.add_connection self
						else
							send_error "this username is already taken - try something else"
						end							
					end
				########################rename##########################
				when "!rename"
					#call method for rename
					if name and params.size > 0
						rename params[0]
					else 
						send_error "you need to be logged in as someone to rename yourself" unless name
						send_error "incorrect paramaters given - you need to specify a new name for yourself" unless params.size > 0
					end
				########################name############################
				when "!name"
					#call method for rename
					if name and params.size > 0
						rename params[0]
					else 
						send_error "you need to be logged in as someone to rename yourself" unless name
						send_error "incorrect paramaters given - you need to specify a new name for yourself" unless params.size > 0
					end
				########################help############################
				when "!help"
					#list  commands - get lines from a help file and then iterate them with send error				
					File.foreach("helpfile") do |line|
						send_error line
					end
				######################new room##########################
				when "!newroom"
					#params: name, topic, parent name, pwd(optional)
					#this is horrid... need a key - value thing here
					params = params.join(" ").split("; ")
					if name and params.size >= 1 #default topic is "", parent is index 0 - root, pass is ""
						rights = DB.get_user_rights name
						puts "#{Time.now}:got rights:"
						puts rights
						if rights[0]["NAME"].gsub(/\W+/,"") == "Admin"
							#now we can add rooms
							new_room_params = {}
							abort = false
							
							params.each do |param|
								paramkey, paramvalue = param.split(":")
								#puts "#{Time.now}: paramkey = #{paramkey}, paramvalue = #{paramvalue}"
								if paramkey == "parent"
									if (DB.find_room paramvalue).count > 0
										new_room_params[paramkey] = (DB.find_room paramvalue)[0]["ID"]
									else
										send_error "room not found: #{paramvalue} - ignoring"
										abort = true
									end
								else
									new_room_params[paramkey] = paramvalue
								end
							end
							
							unless abort
								if (DB.find_room new_room_params).count == 0 
									create_room new_room_params
								else
									send_error "room '#{new_room_params["name"]} already exists"
								end
							else
								send_error "operation aborted"
							end
						else
							send_error "not enough rights to excecute command!"
						end
					else
						send_error "you need to be logged in with admin rights to add rooms" unless name
						send_error "incorrect paramaters: !newroom name:{name}; topic:[topic]; parent:[parent room name]; pass:[password]" unless params.size >= 1
					end
				####################get messages########################
				when "!load"
					if name
						loadmessages params[0] || 35						
					else
						send_error "you need to be logged in as someone to rename yourself" unless name
					end
				####################get rooms###########################	
				when "!loadrooms"
					loadrooms
				####################join room###########################	
				when "!join"	
					*roomname, pass = params					
					if join_room(roomname.join(" "), pass)						
						change_room(DB.find_room(roomname.join(" "))[0]["ID"])
						puts "join room 1"
					else
						if join_room(params.join(" "), "")
							change_room(DB.find_room(params.join(" "))[0]["ID"])
							puts "join room 2"
						else
							send_error "incorrect room name or password"
						end
					end
				##################change room############################	
				when "!changeroom"									
					*roomname, pass = params
					foundroom = DB.find_room roomname.join(" ")
					foundroom2= DB.find_room params.join(" ")
					if foundroom.count > 0 
						change_room foundroom[0]["ID"]
					elsif foundroom2.count > 0 
						change_room foundroom2[0]["ID"]
					else
						send_error "room '#{roomname}' or '#{params.join(" ")}' not found"
					end
				######################clear#############################	
				when "!clear"	
					send_clear
				####################wrong command#######################				
				else
					send_error "command not recognised. Type !help for list of commands"
			end
			puts "#{Time.now}: server compleated command: '#{message}' from #{name} (#{user_rights})"
		else
			if name 
				Chat.send_message_to_all message, room_ID, self
			else
				send_error "you are not logged in - type '!login' to log in or '!register' if you haven't yet"
			end
		end  		
	end
   
	def on_close
		Chat.delete_connection self
	end
  
	def send_error(error_message)
		send({ type: :error, message: error_message}.to_json)
	end

	def	send_clear
		send({ type: :clear}.to_json)		
	end
	
	def send_topic
		topic = ""
		room_info = DB.get_room_info room_ID
		if room_info.count > 0 
			topic = room_info[0]["TOPIC"]
			send({type: :room_change, topic: topic}.to_json)			
		end			
	end
	###################################
	#############actions###############
	###################################
	
	def login name, pass
		#some operation with pass - probably a hash with name or something
		result = false
		usernames = DB.find_user name 
				
		usernames.each do |username|
			
			user = DB.get_user_info(username["USER_ID"])[0]	#there must exist a user with this ID		
			
			if (not result) and (user["PASSWORD"].gsub(/\W+/,"") == DB.hashpass( pass, "33554432").gsub(/\W+/,""))
				#found
				#db_user = DB.get_user_info user["ID"]	
								
				self.name = username["NAME"]
				self.name_ID = username["ID"]
				self.user_ID = user["ID"]
				self.user_rights = user["RIGHTS"]
				self.room_ID = 0 #either 0 or 1 really should be the root room... i'm thinking it's 0
				#get messages
				messages = DB.get_messages room_ID, 35
				messages.each do |message| #sender is a number
					p message
					send_error "#{message["TIME"]} #{message["USERNAME"]}: #{message["TEXT"]}"
				end
				
				DB.update_username_time name
				
				result = true
			end
		end
		return result
	end
	
	def register name, pass
		if DB.find_user(name).count == 0 
			#name not taken - create new user and username
			#creating user
			result = DB.new_user(DB.hashpass(pass, "33554432"), "User")
			result = DB.new_username result["ID"], name
			login name, pass
			true
		else 
			false
		end
	end
	
	def rename newname
		#add a name to the database if it's not taken and tie it to current user
		#check if name is taken
		result = DB.find_user newname
		if result.count == 0 
			result = DB.new_username user_ID, newname
			self.name = result["NAME"]
			self.name_ID = result["ID"]
			DB.update_username_time name
			true
		else
			send_error "this name is taken - try something else"
			false
		end
	end
	
	def join_room  room, pass = ""
		#try adding a user to a room with this password
		#if the password is incorrect, deny(with a message to this user) (just an error message)
		
		#get room info and check pass
		roominfo = DB.find_room room
		if roominfo.count > 0
		
			p roominfo[0]["PASSWORD"]
			p pass
			p roominfo[0]["PASSWORD"] == pass
			p roominfo[0]["PASSWORD"] == nil
			if roominfo[0]["PASSWORD"] == pass or roominfo[0]["PASSWORD"] == nil #i don't really care about the room passes
				#pass ok - add him
				DB.add_user_to_room user_ID, roominfo[0]["ID"] unless DB.user_is_in_room? user_ID, roominfo[0]["ID"]
				true #ok, joined
			else
				send_error "incorrect password"
				false #wrong pass
			end
		else
			false #does not exist
		end
	end	
	
	def change_room room
		#we assume room is correct
		
		#roominfo = DB.get_room_info room
		if DB.user_is_in_room? user_ID, room #roominfo[0]["ID"]				
			self.room_ID = room		
			send_clear
			loadmessages 35
			send_error "you are in room #{(DB.get_room_info room_ID)[0]["NAME"]}"
			send_topic
		else
			send_error "you are not in room '#{(DB.get_room_info room)[0]["NAME"]}' - type 'join name:room name; pass:room password' to join"
		end
	end
	
	def create_room new_room_params				
		DB.new_room new_room_params["name"], new_room_params["topic"], new_room_params["pass"], new_room_params["parent"]
		General.update_room_tree
		send_error "room '#{new_room_params["name"]}' created"
		loadrooms
		true
	end
	
	def loadrooms
		html = General.get_room_tree_html
		Chat.update_room_tree html
	end
	
	def loadmessages count
		messages = DB.get_messages room_ID, count
		messages.each do |message| #sender is a number
			send_error "#{message["TIME"]} #{message["USERNAME"]}: #{message["TEXT"]}"
		end
	end
	
	
end

module Chat
	CONNECTION = []

	module_function

	#################################################################
	##################CONNECTIONS FUNCTIONS##########################
	#################################################################
  
	def add_connection(connection)
		CONNECTION.push connection
		send_message_to_all("#{connection.name} присоединился к чату", 0, connection)
		#add this nigga to the room-users list for root if he's not in yet
		DB.add_user_to_room connection.user_ID, 0 unless DB.user_is_in_room? connection.user_ID, 0 #adds users to root if they are not in yet
	end

	def delete_connection(connection)
		#send_message_to_all "пользователь #{connection.name} вышел из чата", 0, connection
		
		
		#userrooms = DB.get_user_rooms connection.user_ID
		#userrooms.each do |userroom|
			#room = userroom["ROOM"]
			#send_message_to_all "пользователь вышел из чата", room, connection#
			#DB.add_message connection.user_ID, room, "пользователь вышел из чата"
		#end
		
		CONNECTION.delete connection		
	end
  
	def send_message_to_all(message, room = 0, con) 
		if con.name #must be a logged in user to user this method
			msg = { type: :chat_message, username: con.name, message: message, room: room}
			CONNECTION.each do |connection|
				if connection and connection.user_ID and DB.user_is_in_room?(connection.user_ID, room)
					if connection.room_ID == room					
						connection.send msg.to_json	
					else
						#send update for a message in this room
					end
				end	#if con exists and user is in this room
			end		
			DB.add_message con.user_ID, room, message #add to DB
		end		
	end
	
	def update_room_tree html
		msg = { type: :room_update, message: html}
		CONNECTION.each do |connection|
			connection.send msg.to_json
		end
	end
end

module DB
	Conn = PG.connect( :dbname => "kmar", :user => "kmar", :password => "******")

	module_function
	#################################################################
	#####################DATABASE FUNCTIONS##########################
	#################################################################
    
	#################
	####add stuff####
	#################
  
	def add_message user, room, message
		#adds message to DB
		cols = words_in_double_brackets("SENDER, ROOM, TEXT, TIME".split(", ")).join(", ")
		values = ( "'#{user}', '#{room}', '#{message.gsub("'","''").gsub("\"","\"\"")}', '#{Time.now}'")
		Conn.exec("INSERT INTO \"MESSAGES\" (#{cols}) VALUES (#{values});")
	end
  
	def add_user_to_room user, room
		cols  = words_in_double_brackets("ROOM, USER_ID".split(", ")).join(", ")
		values = words_in_single_brackets("#{room}, #{user}".split(", ")).join(", ")
		Conn.exec("INSERT INTO \"ROOMUSERS\" (#{cols}) VALUES ( #{values});")
	end
  
	def new_user pass = "", rights = "User" #User is normal rights
		right_id = DB.find_rights(rights)[0]["ID"]
		if pass 
			cols = words_in_double_brackets("RIGHTS, PASSWORD".split(", ")).join(", ")
			values = words_in_single_brackets("#{right_id}, #{pass}".split(", ")).join(", ")
		else
			cols = words_in_double_brackets("RIGHTS".split(", ")).join(", ")
			values = words_in_single_brackets("#{rights}").join(", ")
		end
		Conn.exec("INSERT INTO \"USERS\" (#{cols}) VALUES ( #{values} );")		
		result = Conn.exec("SELECT * FROM \"USERS\" ORDER BY \"ID\" DESC LIMIT 1;")[0] #as long as we NEVER reset numbering in our database, we'll be fine		
	end

	def new_username user, username
		cols = words_in_double_brackets("USER_ID, USERNAME".split(", ")).join(", ")
		values = words_in_single_brackets("#{user}, #{username}".split(", ")).join(", ")
		Conn.exec("INSERT INTO \"USERNAMES\" (#{cols}) VALUES ( #{values});")
		result = Conn.exec("SELECT * FROM \"USERNAMES\" ORDER BY \"ID\" DESC LIMIT 1;")[0] 
	end
  
	def new_room name, topic = nil, pass = nil, parent = nil #most of these are optional
		text = "INSERT INTO \"ROOMS\" (\"NAME\""
		text += ",\"PASSWORD\"" unless pass == "" or pass.nil?
		text += ",\"TOPIC\"" unless topic == "" or topic.nil?
		text += ",\"PARENT\"" unless parent.nil?		
		
		text += ") VALUES ( '#{name.gsub("'","''")}'"
		
		text += ",'#{pass.gsub("'","''")}'" unless pass == "" or pass.nil?
		text += ",'#{topic.gsub("'","''")}'" unless topic == "" or topic.nil?
		text += ",'#{parent.gsub("'","''")}'" unless parent.nil?
		
		text += ");"
		text
		Conn.exec(text)
	end
  
	#################
	##remove stuff###
	#################
  
	def remove_user_from_room user, room
		Conn.exec("DELETE FROM \"ROOMUSERS\" WHERE \"USER_ID\" = '#{user}' AND \"ROOM\" = '#{room}';")
	end
  
	def destroy_room room, cascade = false #if cascade is true, child rooms will also be destroyed, else they will be linked to this rooms parent instead
		if cascade
			#get children, call destroy room on them
			res = Conn.exec("SELECT \"ID\" FROM \"ROOMS\" WHERE \"PARENT\" = '#{room}'")
			res.each do |child| 
				destroy_room child, true #TODO should work... test in irb on frankie later on
			end
			#TODO delete the room and all links to it (messages, roomusers, tasks and so on...
		else
			#get children, set their parent to this room's parent
			Conn.exec("UPDATE \"ROOMS\" SET \"PARENT\"  =  \"PARENT\".\"PARENT\" WHERE \"PARENT\" = '#{ROOM}'")
			Conn.exec("DELETE FROM \"ROOMS\" WHERE \"USER_ID\" = '#{user}' AND \"ID\" = '#{room}';")
		end
	end 
  
	#################
	##change stuff###
	#################
  
	def change_user_rights user, rights = 2 #2 is normal rights... for now
		Conn.exec("UPDATE \"USERS\" SET \"RIGHTS\" = '#{rights}' WHERE \"USER\" = '#{user}'")
	end
  
	def change_room room, name = nil, topic = nil, pass = nil, parent = nil
		#nil fields are ignored and will not be changed
		operations = []
		operations << "\"NAME\" = '#{name}'" if name
		operations << "\"PASSWORD\" = '#{pass}'" if pass
		operations << "\"TOPIC\" = '#{topic}'" if topic
		operations << "\"PARENT\" = '#{parent}'" if parent		
		
		text = "UPDATE \"ROOMS\" SET #{operations.join(", ")} WHERE \"ID\" = '#{room}'"
	end
	
	def update_username_time username
		Conn.exec("UPDATE \"USERNAMES\" SET \"LAST_USED\" = '#{Time.now}' WHERE \"USERNAME\" = '#{username}' ")
	end
  
	#################
	###find stuff####
	#################
  
	def find_user name
		res = Conn.exec("SELECT * FROM \"USERNAMES\" WHERE \"USERNAME\" = '#{name}'")
	end
	
	def find_rights right
		res = Conn.exec("SELECT * FROM \"RIGHTS\" WHERE \"NAME\" = '#{right}'")
	end
	
	def find_room name
		res = Conn.exec("SELECT \"ID\" FROM \"ROOMS\" WHERE \"NAME\" = '#{name}';")
	end
  
	def get_user_info user
		res = Conn.exec("SELECT * FROM \"USERS\" WHERE \"ID\" = '#{user}'")
	end

	def user_is_in_room? user, room
		Conn.exec("SELECT * FROM \"ROOMUSERS\" WHERE \"USER_ID\" = '#{user}' AND \"ROOM\" = '#{room}'").count > 0
	end
	
	def get_user_rights name
		user = DB.find_user name
		right = DB.get_user_info(user[0]["USER_ID"])[0]
		DB.get_right_info right["RIGHTS"]
	end
	
	def get_right_info right
		Conn.exec("SELECT * FROM \"RIGHTS\" WHERE \"ID\" = #{right};")
	end
	
	def get_room_users room
		Conn.exec("SELECT * FROM \"ROOMUSERS\" WHERE \"ROOM\" = '#{room}'")
	end
	
	def get_room_info room
		Conn.exec("SELECT * FROM \"ROOMS\" WHERE \"ID\" = #{room};")
	end
	
	def get_user_rooms user
		Conn.exec("SELECT * FROM \"ROOMUSERS\" WHERE \"USER_ID\" = '#{user}'")
	end
	
	def get_messages room, count
		Conn.exec(
		"SELECT * FROM
			(SELECT * FROM 
				(SELECT * FROM 
					\"MESSAGES\" 
				WHERE \"ROOM\" = '#{room}'
				) AS \"THISROOMMESSAGES\" 
			INNER JOIN 
				(SELECT * FROM 
					\"USERNAMES\" 
				INNER JOIN
					(SELECT 
						MAX(\"LAST_USED\"), 
						\"USER_ID\" AS \"USER_ID2\"
					FROM 
						\"USERNAMES\" 
					GROUP BY \"USER_ID\"
					) AS \"GROUPEDUSERNAMES\"
				ON ( 
					\"max\" = \"LAST_USED\" 
					AND \"USERNAMES\".\"USER_ID\" = \"GROUPEDUSERNAMES\".\"USER_ID2\"
				)
				) AS \"LASTUSEDNAMES\"
			ON ( \"SENDER\" = \"USER_ID\")
			ORDER BY \"TIME\" DESC LIMIT '#{count}') AS \"ROOMMESSAGESWITHUSERS\"
		ORDER BY \"TIME\" ASC;")
	end
	
	def get_rooms_with_parent parent = nil
		if parent
			Conn.exec("SELECT * FROM \"ROOMS\" WHERE \"PARENT\" = '#{parent}';")
		else
			Conn.exec("SELECT * FROM \"ROOMS\" WHERE \"PARENT\" IS NULL;") #returns only root rooms
		end
	end
	
	def get_all_rooms
		Conn.exec("SELECT * FROM \"ROOMS\";")
	end
	#################
	#####auxillery###
	#################
	
	def words_in_double_brackets words
		words.map{|word| "\"" + word + "\""}
	end
	
	def words_in_single_brackets words
		words.map{|word| "'" + word + "'"}
	end
	
	def hashpass pass, seed
		Digest::SHA256.hexdigest(seed + pass)
	end
	
	def create_root_room
		if Conn.exec("SELECT * FROM \"ROOMS\" WHERE \"ID\" = 0").count == 0
			puts "Server didn't find root room in DB - creating new one"
			Conn.exec("INSERT INTO \"ROOMS\" (\"ID\", \"NAME\") VALUES (0, 'ROOT')")			
		end
	end 
	
	def create_rights
		"Banned, Muted, User, Moderater, Admin".split(", ").each do |right|
			if Conn.exec("SELECT * FROM \"RIGHTS\" WHERE \"NAME\" = '#{right}'").count == 0								
				puts "Server didn't find the '#{right}' right - attempting to add it automatically"
				Conn.exec("INSERT INTO \"RIGHTS\" (\"NAME\") VALUES ('#{right}')")			
			end
		end
	end
end

module General

	@room_tree = {}
	
	module_function
	
	def update_room_tree	
		room_tree = Hash.new
		room_tree[:children] =  []
		room_tree = get_children room_tree #should give whole tree
		@room_tree = room_tree
		return true
	end	
	
	def get_children tree, curr_room = nil
		#get an array of children		
		children = DB.get_rooms_with_parent curr_room #returns all rooms where curr_room is the parent
		children_array = []
		children.each do |child| #adds children to an array in the form of hashes
			child_hash = {id: child["ID"], parent: child["PARENT"], sql: child, children: []}
			child_with_children = General.get_children(child_hash, child["ID"])
			children_array << child_with_children			
		end
		tree[:children] = children_array
		return tree
	end
	
	def get_room_tree_html #should probably give html or something		
		#now generate some html	
		html = ""	
		html = "
		<div class=\"treeview\">
			<ul>
				<li>
					<div><p><a href=\"#\" class=\"sc\" onclick=\"return UnHide(this)\">&#9660;</a>
						<a href=\"#\">Rooms:</a></p></div>
					<ul>
			"
		html = generate_html html, @room_tree[:children][0] #TODO: allow for several root rooms lter on
		html += "</ul></li></ul></div>"
		html
	end

	def generate_html full_html, node	
		if node[:children].empty?
			#this is a leaf
			full_html += leaf_html node
		else
			#this is a node
			#generate some html for node, add children in list			 
			full_html += node_html node
			full_html += node[:children].inject("") do |children_html, child| 
				generate_html(children_html, child)
			end
			full_html += "</ul></li>"
		end		
		full_html
	end
	
	def leaf_html leaf
		html = "
		<li>
			<div>
				<p>
					<a class=\"room_item\" onclick=\"change_room(this)\">#{leaf[:sql]["NAME"]}</a>
				</p>
			</div>
		</li>"
	end
	
	def node_html node
		html = "
			<li class=\"cl\">
				<div>
					<p>
						<a class=\"sc\" onclick=\"return UnHide(this)\">&#9658;</a>
						<a class=\"room_item\" onclick=\"change_room(this)\">#{node[:sql]["NAME"]}</a>
					</p>
				</div>
			<ul id=\"leaflist\">		
		"
	end
end

DB.create_root_room
DB.create_rights
General.update_room_tree #so that we have a room tree ready
puts "#{Time.now}: server is starting"
EM.run do
	EM.start_server '0.0.0.0', '9001', Chatconnection
end
puts "server is dead?"
