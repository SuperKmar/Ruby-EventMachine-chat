$ ->
	client = new WebSocket('ws://192.168.1.36:9001')
	client.onopen = ->
		console.log 'connected'
		
	client.onmessage = (message) ->
		
		json = JSON.parse message.data
		switch json.type
			when 'error'
				add_entry_to_log json.message
			when 'chat_message'				
				add_chat_message json
			when 'room_update'
				update_rooms json.message
			when 'clear'
				clear_chat message
			when 'room_change'
				room_change json
		
		
	$('#chat_input').keyup (e) ->
		if e.keyCode == 13
			message = $('#chat_input').val()
			client.send message
			$('#chat_input').val ''
			`window.scrollTo(0,document.body.scrollHeight)`
	
	$chat_log = $('#chat_log')
	add_entry_to_log = (message) ->
		$chat_log.append "<li> #{message} </li>"		
	
	add_chat_message = (json) -> 
		add_entry_to_log "<i>#{json.username}:</i> #{json.message}"
		
	update_rooms = (message) ->
		$("#sidebar").html message
	
	clear_chat = (message) ->
		$chat_log.html "<li> cleared </li>"

	$(document).on('click', '.room_item', ( ->
		client.send "!changeroom #{this.innerText}"
	));
	
	room_change = (json) ->
		$("#topic_area").html = json.topic
