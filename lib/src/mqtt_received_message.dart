/*
  * Package : mqtt5_client
  * Author : S. Hamblett <steve.hamblett@linux.com>
  * Date   : 10/05/2020
  * Copyright :  S.Hamblett
  */

part of '../mqtt5_client.dart';

/// Represents a MQTT message that has been received from a broker.
class MqttReceivedMessage<T> {
  /// The topic the message was received on.
  String? topic;

  /// The payload of the message received.
  T payload;

  void Function()? ack;

  /// Initializes a new instance of an MqttReceivedMessage class.
  MqttReceivedMessage(this.topic, this.payload);
}

extension MqttReceivedMessageX on MqttReceivedMessage<MqttMessage> {
  MqttPublishMessage? get publishMessage =>
      payload is MqttPublishMessage ? payload as MqttPublishMessage : null;

  int? get packetId => publishMessage?.variableHeader?.messageIdentifier;

  String? get payloadString {
    final msg = publishMessage;
    if (msg?.payload.message == null) return null;
    return MqttUtilities.bytesToStringAsString(msg!.payload.message!);
  }
}
