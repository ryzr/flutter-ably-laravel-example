import 'dart:async';

import 'package:ably_flutter/ably_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryzr_ably/ably.dart';

class ExamplePage extends ConsumerStatefulWidget {
  const ExamplePage({super.key});

  @override
  ConsumerState<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends ConsumerState<ExamplePage> {
  Stream<Message>? stream;

  @override
  Widget build(BuildContext context) {
    final userId = dotenv.env['USER_ID'] ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Example'),
      ),
      body: Center(
        child: ref.watch(ablyServiceProvider(userId)).maybeWhen(data: (ably) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              StreamBuilder(
                  stream: ably.connection,
                  builder: (context, snapshot) {
                    return snapshot.hasData ? Text('Connection state: ${snapshot.data!.current} ${snapshot.data!.reason}') : const CircularProgressIndicator();
                  }),
              if (stream != null)
                StreamBuilder(
                    stream: stream,
                    builder: (context, snapshot) {
                      return snapshot.hasData ? Text('Latest event: ${snapshot.data!.name ?? 'Unknown'}') : const CircularProgressIndicator();
                    }),
              if (stream == null)
                ElevatedButton(
                  onPressed: () {
                    ably.private('App.Models.User.$userId').then((channel) {
                      setState(() {
                        stream = channel.subscribe();
                      });
                    }).catchError((e) {
                      debugPrint('Error subscribing: $e');
                    });
                  },
                  child: Text('Subscribe private:App.Models.User.$userId'),
                ),
            ],
          );
        }, orElse: () {
          return const CircularProgressIndicator();
        }),
      ),
    );
  }
}
