// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:project_app/audio/audio.dart';
import 'package:project_app/audio/classifier.dart';
import 'package:random_color/random_color.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'audio/main.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  RandomColor randomColorGen = RandomColor();

  UsbPort? _port;
  String _status = "Idle";
  List<Widget> _ports = [];
  List<Widget> _serialData = [];
  final List<int> _data = [];
  late final ScrollController _controller;
  late Stream<String> lines;

  ///
  final List<int> _chunks = [];
  late final StreamController<Uint8List> _analogChunks;

  //for classifier

  late Timer _timer;

  late Classifier _classifier;

  List<Category> preds = [];

  // RandomColor randomColorGen = RandomColor();

  Category? prediction;

  late StreamController<List<Category>> streamController;

  ////////////////

  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  UsbDevice? _device;

  final sampleRate = 8000;

  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();

    _analogChunks = StreamController<Uint8List>();
    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      _getPorts();
      print("object");
    });

    _getPorts();

///////////////
    streamController = StreamController();

    // initPlugin();
    init();
    Future.delayed(const Duration(seconds: 5)).then((value) {
      _timer = Timer.periodic(const Duration(seconds: 2), (Timer t) {
        streamController.add(_classifier.predict(_data));
      });
    });
  }

  Future<void> initPlugin() async {
    // _audioStream = _recorder.audioStream.listen((data) {
  }

  Future<void> init() async {
    _classifier = Classifier();
    await _classifier.loadModel();
    await _classifier.loadLabels();
  }

  ////
  ///
  Future<void> openFileAndRead() async {
    if (await Permission.storage.request().isGranted) {
      File file = File("/storage/emulated/0/Download/data.txt");
      lines = file
          .openRead()
          .transform(utf8.decoder) // Decode bytes to UTF-8.
          .transform(const LineSplitter());
      // lines.listen((line) {
      for (var byte in Audio.samples) {
        _chunks.add(byte);
        if (_chunks.length > 1200) {
          _analogChunks.add(Uint8List.fromList(_chunks));
          _chunks.clear();
        }

        // });

        setState(() {
          _serialData.add(Text(byte.toString()));
          // if (_serialData.length > 20) {
          //   _serialData.removeAt(0);
          // }
        });
      }

      _analogChunks.stream.listen((event) {
        print(event);
        if (_data.length > 2 * sampleRate) {
          print(_data.length);
          _data.clear();
        }
        log(event.toString());
        _data.addAll(event);
      });
      streamController.stream.listen((event) {
        setState(() {
          preds = event;
        });
      });
    }
  }

  Future<bool> _connectTo(device) async {
    _serialData.clear();

    if (_subscription != null) {
      _subscription!.cancel();
      streamController.close();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port!.close();
      _port = null;
    }

    if (device == null) {
      _device = null;
      setState(() {
        _status = "Disconnected";
      });
      return true;
    }

    _port = await device.create();
    if (await (_port!.open()) != true) {
      setState(() {
        _status = "Failed to open port";
      });
      return false;
    }
    _device = device;

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
        115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _transaction = Transaction.stringTerminated(
        _port!.inputStream as Stream<Uint8List>, Uint8List.fromList([13, 10]));

    _subscription = _transaction!.stream.listen((String line) {
      final l = line.split(":");
      final byte = () {
        if (l.length < 2) {
          return 1;
        } else {
          return int.parse(l[1]);
        }
      }();
      _chunks.add(byte);
      if (_chunks.length > 1200) {
        _analogChunks.add(Uint8List.fromList(_chunks));
        _chunks.clear();
      }

      // });

      setState(() {
        _serialData.add(Text(byte.toString()));
        // if (_serialData.length > 20) {
        //   _serialData.removeAt(0);
        // }
      });
    });
    await Future.delayed(const Duration(milliseconds: 1500));

    _analogChunks.stream.listen((event) {
      log(event.toString());
      if (_data.length > 2 * sampleRate) {
        print(_data.length);
        _data.clear();
      }
      _data.addAll(event);
    });
    streamController.stream.listen((event) {
      setState(() {
        preds = event;
      });
    });

    setState(() {
      _status = "Connected";
    });
    return true;
  }

  void _getPorts() async {
    _ports = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (!devices.contains(_device)) {
      _connectTo(null);
    }
    print(devices);

    devices.forEach((device) {
      _ports.add(ListTile(
          leading: Icon(Icons.usb),
          title: Text(device.productName!),
          subtitle: Text(device.manufacturerName!),
          trailing: ElevatedButton(
            child: Text(_device == device ? "Disconnect" : "Connect"),
            onPressed: () {
              _connectTo(_device == device ? null : device).then((res) {
                _getPorts();
              });
            },
          )));
    });

    setState(() {
      print(_ports);
    });
  }

  @override
  void dispose() {
    super.dispose();
    streamController.close();
    _analogChunks.close();
    _connectTo(null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: Scaffold(
      appBar: AppBar(
        title: const Text('USB Serial Plugin example app'),
      ),
      body: Center(
          child: Column(children: <Widget>[
        Text(
            _ports.length > 0
                ? "Available Serial Ports"
                : "No serial devices available",
            style: Theme.of(context).textTheme.headline6),
        ..._ports,
        Text('Status: $_status\n'),
        Text('info: ${_port.toString()}\n'),
        ListTile(
          title: TextField(
            controller: _textController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Text To Send',
            ),
          ),
          trailing: ElevatedButton(
            child: Text("Send"),
            onPressed: _port == null
                ? null
                : () async {
                    if (_port == null) {
                      return;
                    }
                    String data = _textController.text + "\r\n";
                    await _port!.write(Uint8List.fromList(data.codeUnits));
                    _textController.text = "";
                  },
          ),
        ),
        Text("Result Data", style: Theme.of(context).textTheme.headline6),
        // Container(
        //   height: 400,
        //   width: double.infinity,
        //   color: Colors.yellow,
        //   alignment: Alignment.center,
        //   child: Center(
        //     child: ListView.builder(
        //         controller: _controller,
        //         itemCount: _serialData.length,
        //         itemBuilder: ((context, index) {
        //           return _serialData[index];
        //         })),
        //   ),
        // ),

        InkWell(
          onLongPress: () {
            streamController.close();
            _timer.cancel();
            _analogChunks.close();
            print("cancelled");
          },
          onTap: () async {
            await openFileAndRead();
          },
          child: Container(
            height: 60,
            width: 200,
            color: Colors.black,
          ),
        ),

        /////////////////////
        ListView.builder(
          shrinkWrap: true,
          itemCount: preds.length,
          itemBuilder: (context, i) {
            final color = randomColorGen.randomColor(
                colorBrightness: ColorBrightness.light);
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preds.elementAt(i).label,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blueAccent),
                    ),
                  ),
                  Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      PredictionScoreBar(
                        ratio: 1,
                        color: color.withOpacity(0.1),
                      ),
                      PredictionScoreBar(
                        ratio: preds.elementAt(i).score,
                        color: color,
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        ),
      ])),
    ));
  }
}
