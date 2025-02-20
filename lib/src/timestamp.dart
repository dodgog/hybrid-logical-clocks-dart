typedef LogicalTime = DateTime;

class Timestamp implements Comparable<Timestamp>{
  const Timestamp(this.logicalTime, this.clientNode, this.counter);

  final LogicalTime logicalTime;
  final ClientNode clientNode;
  final int counter;

  @override
  int compareTo(Timestamp other) {
    final timeCompare = logicalTime.compareTo(other.logicalTime);
    if (timeCompare != 0) return timeCompare;
    final counterCompare = counter.compareTo(other.counter);
    if (counterCompare != 0) return counterCompare;
    return clientNode.compareTo(other.clientNode);
  }

  Timestamp copyWith({
    LogicalTime? logicalTime,
    ClientNode? clientNode,
    int? counter,
  }) {
    return Timestamp(
      logicalTime ?? this.logicalTime,
      clientNode ?? this.clientNode,
      counter ?? this.counter,
    );
  }
}

class ClientNode implements Comparable<ClientNode> {
  const ClientNode(this.clientNodeId);

  final String clientNodeId;

  String pack(){
    return clientNodeId;
  }

  const ClientNode.fromPacked(this.clientNodeId);

  @override
  int compareTo(ClientNode other) => clientNodeId.compareTo(other.clientNodeId);

  @override
  bool operator ==(Object other) {
    if (Object !is ClientNode){
      return false  ;
    }
    return clientNodeId == (other as ClientNode).clientNodeId;
  }

  @override
  int get hashCode => clientNodeId.hashCode;
}
