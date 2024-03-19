import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:ably_flutter/ably_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryzr_ably/jwt.dart';

class AblyService {
  late final Realtime _client;
  final String userId;

  String? currentChannelName;
  TokenDetails? currentToken;

  AblyService(
      {required String key,
      required this.userId,
      required Future<TokenDetails> Function(String? channelName, TokenParams params, TokenDetails? currentToken) authCallback}) {
    _client = Realtime(
        options: ClientOptions(
      key: key,
      logLevel: LogLevel.verbose,
      authCallback: (tokenParams) async {
        debugPrint('Authorizing user $userId for channel $currentChannelName');

        currentToken = await authCallback(currentChannelName, tokenParams, currentToken);
        debugPrint('Current Capabilities: ${currentToken?.capability ?? 'none'}');

        return currentToken!;
      },
      tls: true,
      queryTime: true,
      idempotentRestPublishing: true,
    ));
  }

  Stream<ConnectionStateChange> get connection => _client.connection.on();
  Future<RealtimeChannel> private(String channelName) {
    return connectToChannel("private:$channelName");
  }

  Future<RealtimeChannel> presence(String channelName) {
    return connectToChannel("presence:$channelName");
  }

  Future<RealtimeChannel> connectToChannel(String channelName) async {
    currentChannelName = channelName;

    debugPrint('Checking if we have already authorized $currentChannelName for user $userId');

    if (!hasCapability(channelName, '*')) {
      await _client.auth.authorize(
          tokenParams: TokenParams(
              clientId: userId,
              capability: jsonEncode({
                channelName: ['*']
              })));
    }

    debugPrint('Connecting to: $channelName');

    final channel = _client.channels.get(channelName);
    channel.on().listen((event) {
      if (event.current == ChannelState.failed) {
        debugPrint('Channel error: ${event.reason?.message} ($channelName)');
      } else {
        debugPrint('Channel state change: ${event.current.name} ($channelName)');
      }
    });

    return channel;
  }

  bool hasCapability(String channelName, String capability) {
    final parsed = jsonDecode(currentToken?.capability ?? '{}');

    return parsed is Map && parsed[channelName] is List<dynamic> && parsed[channelName].contains(capability);
  }

  Future<void> connect() async {
    try {
      await _client.connect();
      debugPrint('Successfully connected to Ably');
    } catch (error, stacktrace) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stacktrace, context: ErrorDescription('Ably: connect')));

      rethrow;
    }
  }

  void disconnect() async {
    try {
      _client.close();
      debugPrint('Successfully disconnected from Ably');
    } catch (error, stacktrace) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stacktrace, context: ErrorDescription('Ably: disconnect')));

      rethrow;
    }
  }
}

final ablyServiceProvider = FutureProvider.autoDispose.family<AblyService, dynamic>((ref, userId) async {
  AblyService? service;

  ref.onDispose(() {
    try {
      service?.disconnect();
    } catch (e) {
      //
    }
  });

  final apiToken = dotenv.env['API_TOKEN'] ?? '';

  final dio = Dio(BaseOptions(baseUrl: dotenv.env['APP_URL'] ?? ''));

  service = AblyService(
      key: dotenv.env['ABLY_KEY'] ?? '',
      userId: userId.toString(),
      authCallback: (String? channelName, TokenParams params, TokenDetails? currentToken) async {
        final response = await dio.post('/broadcasting/auth',
            options: Options(
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $apiToken',
              },
            ),
            data: {
              'channel_name': channelName,
              'token': currentToken?.token,
            });

        final jwt = response.data['token'];

        final parsed = parseJwt(jwt);

        return TokenDetails(
          jwt,
          capability: parsed['x-ably-capability'],
          clientId: parsed['x-ably-clientId'],
          expires: parsed['exp'] * 1000 as int,
          issued: parsed['iat'] * 1000 as int,
        );
      });

  return service..connect();
});
