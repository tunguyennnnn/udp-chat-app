$(document).ready(updateClient);

function updateClient(){
  var client = createStreamingClient('http://localhost:8000', progress, function(data){console.log(data)})
}



function createStreamingClient(url, progress, finished){
  var xhr = new XMLHttpRequest(), received =0;
  xhr.open('get', url, true);
  xhr.onreadystatechange = function(){
    var result;
    if (xhr.readyState == 3){
      result = xhr.responseText.substring(received);
      received += result.length;
      console.log(333);
      progress(result);
    }
    else if (xhr.readyState == 4){
      finished(xhr.responseText)
    }
  }
  xhr.send(null);
  return xhr;
}
var entities = [];
function progress(result){
  var result = JSON.parse(result);
  for (var key in result){
    var type = result[key].type;
    var message = result[key].message;
    var id = result[key].sender;
    var ip = result[key].ip
    console.log(id);
    if (entities[id]){
      entities[id].addMessage(message);
    }
    else{
      entities[id] = new Entity(type, id, '', ip)
      entities[id].addMessage(message);
    }
  }
}

var x ;


function Entity(type, id, name, ip){
  var self = this;
  x = self;
  this.name = name;
  this.id = id;
  var partitions = id.split('-');
  this.ip = ip;
  this.port = partitions[1];
  if (type === 'client'){
    $('#client-grid').append((generateHtml(this.id)));
  }
  else{
    $('#server-grid').append((generateHtml(this.id)));
  }
  this.$entity = $('#' + this.id);
  this.$entity.find('.register').first().off().on('click',function(){
    $(this).find('.box-area').first().show(function(){
      var $self = $(this);
      $(this).find('.send-to-server').first().off().on('click',function(){
        var server = $self.find('.ip').first().val();
        var port = $self.find('.port').first().val();
        post({ip: self.ip, port: self.port, message: `register ${server} ${port}`})
      })
    });
  }).mouseleave(function(){
    $(this).find('.box-area').first().hide()
  })

  this.$entity.find('.publish').first().click(function(){
    $(this).find('.box-area').first().show();
  }).mouseleave(function(){
    $(this).find('.box-area').first().hide()
  });

  this.$entity.find('.bye').first().click(function(){
    $(this).find('.box-area').first().show();
  }).mouseleave(function(){
    $(this).find('.box-area').first().hide()
  });

  function initChatBox(){
    var friend = null;
    var $chatBox = self.$entity.find('.chat-box').first();
    var $sendButton = $chatBox.find('.send-chat-message').first();
    var $select = $chatBox.find('.friends-chat').first().selectize({
      maxItems: 1,
      valueField: 'id',
      labelField: 'name',
      onItemAdd: function(value, $item){
        console.log(value)
        friend = value;
      }
    });
    var selectize = self.selectize = $select[0].selectize;
    $sendButton.on('click', function(){
      var chatMessage = $chatBox.find('.chat-message').first().val();
      if (friend){
        post({ip: self.ip, port: self.port, message: `chat_message ${friend} ${chatMessage}`})
      }
    })
  }
  initChatBox();



  function generateHtml(id){
    var html = '<div class="entity" id="' + id +'">'
    html +=      '<div class="entity-header">'
    html +=        '<span class="label label-primary register">'
    html +=          'Register'
    html +=          '<div class="box-area input-group">'
    html +=            '<div class="col-xs-12"><input type="text" class="form-control ip" placeholder="ip: '+ self.ip + '" aria-describedby="sizing-addon1"></div>'
    html +=            '<div class="col-xs-12"><input type="text" class="form-control port" placeholder="port: ' + self.port + '" aria-describedby="sizing-addon1"></div>'
    html +=            '<div class="btn-group col-xs-12" role="group" style="z-index: 1000"><button type="button" class="btn btn-default send-to-server">Send</button></div>'
    html +=          '</div>'
    html +=        '</span>'
    html +=        '<span class="label label-primary publish">'
    html +=          'Publish'
    html +=          '<div class="box-area input-group">'
    html +=            '<div class="btn-group col-xs-12" role="group" aria-label="..." style="z-index: 1000"><button type="button" class="btn btn-default">ON</button><button type="button" class="btn btn-default">OFF</button></div>'
    html +=            '<div class="col-xs-12"><input type="text" class="form-control" placeholder="friends" aria-describedby="sizing-addon1"></div>'
    html +=            '<div class="btn-group col-xs-12" role="group" style="z-index: 1000"><button type="button" class="btn btn-default send-to-server">Send</button></div>'
    html +=          '</div>'
    html +=        '</span>'
    html +=        '<span class="label label-primary req-info">'
    html +=           'Request Information'
    html +=        '</span>'
    html +=        '<span class="label label-primary chat">Chat</span>'
    html +=        '<span class="label label-primary bye">'
    html +=         'Bye'
    html +=         '<div class="box-area bye-selection">'
    html +=           '<select class="bye-chat"></select>'
    html +=         '</div>'
    html +=        '</span>'
    html +=      '</div>'
    html +=      '<div class="entity-body">'
    html +=      '</div>'
    html +=      '<div class="chat-box"><div class="col-xs-3"><select class="friends-chat"></select></div><input class="chat-message col-xs-7"></input><button type="button" class="send-chat-message col-xs-2">Send</button></div>'
    html +=    '</div>'
    return html;
  }

  this.addMessage = function(message){
    if (message.indexOf('FINDResp') != -1){
      var friendName = message.split(' ')[6];
      this.selectize.addOption({name: friendName, id: friendName})
    }
    self.$entity.find('.entity-body').first().append('<span>'+ message + '</span><br>')
  }
}

function post(message){
  $.ajax({
    url: 'http://localhost:8000',
    type: 'POST',
    data: message,
    done: function(data){

    }
  })
}
