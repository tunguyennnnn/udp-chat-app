$(document).ready(updateClient);

function updateClient(){
  var stream = new EventSource('http://localhost:8000')
  stream.onmessage = function(event){

    console.log(event.data);
  }
}
