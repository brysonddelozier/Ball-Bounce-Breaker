import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ball_bounce_breaker/pages/game_state.dart';
import 'package:ball_bounce_breaker/models/block.dart';
import 'package:sensors_plus/sensors_plus.dart';

class GameScreen extends StatefulWidget {
  final GameState gameState;
  
  const GameScreen({super.key, required this.gameState});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Tunable values — adjust these to change feel/look.
  static const double _paddlewidth = 135.0;
  static const double _paddleheight = 10.0;
  static const double _paddleSensitivity =
      0.06; // higher = more reactive to tilt
  static const double _paddleBottom = 40.0; // gap from bottom of screen
  static const double _ballSize = 20.0;
  static const double _ballSpeed = 4.0; // pixels per tick, ~60 ticks/sec
  static const Color _paddleColor = Colors.white;
  static const Color _ballColor = Colors.white;
  static int _numLives = 2;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _gameTimer; // drives the ball while playing

  double _paddleX = 0.0; // -1.0 (left) to 1.0 (right)
  double _ballX = 0.0;
  double _ballY = 0.0;
  double _ballSpeedX = _ballSpeed;
  double _ballSpeedY = -_ballSpeed; // starts moving up
  Size _screenSize = Size.zero; // set once LayoutBuilder measures the screen
  bool _isPlaying = false;

  // Block grid — built once when the screen loads.
  final List<Block> _blocks = buildBlocks();

  // Real pixel position of the paddle, derived from _paddleX and screen size.
  double get _paddleTop => _screenSize.height - _paddleBottom - _paddleheight;
  double get _paddleLeft =>
      (_screenSize.width - _paddlewidth) * (_paddleX + 1) / 2;

  @override
  void initState() {
    super.initState();
    widget.gameState.score = 0;
    widget.gameState.lives = _numLives;
    // Listen for tilt and move the paddle, but only once the game has started.
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      if (!_isPlaying) return;
      setState(() {
        _paddleX -= event.x * _paddleSensitivity;
        _paddleX = _paddleX.clamp(-1.0, 1.0);
      });
    });
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gameTimer?.cancel();
    super.dispose();
  }

  // Starts the ball moving when Start is pressed.
  void _startGame() {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true;
    });
    _gameTimer =
        Timer.periodic(const Duration(milliseconds: 16), (_) => _moveBall());
  }

  void _resetGame() {
    _paddleX = 0.0;
    final paddleTop = _screenSize.height - _paddleBottom - _paddleheight;
    _ballX = _screenSize.width / 2 - _ballSize / 2;
    _ballY = paddleTop - _ballSize - 4.0;
    _ballSpeedX = _ballSpeed;
    _ballSpeedY = -_ballSpeed;
  }

  // Advances the ball and checks it against walls and the paddle.
  void _moveBall() {
    if (_screenSize == Size.zero) return;

    setState(() {
      _ballX += _ballSpeedX;
      _ballY += _ballSpeedY;

      // Bounce off left/right walls.
      if (_ballX <= 0) {
        _ballX = 0;
        _ballSpeedX = -_ballSpeedX;
      } else if (_ballX >= _screenSize.width - _ballSize) {
        _ballX = _screenSize.width - _ballSize;
        _ballSpeedX = -_ballSpeedX;
      }

      // Bounce off the top wall.
      if (_ballY <= 0) {
        _ballY = 0;
        _ballSpeedY = -_ballSpeedY;
      }

      // Bounce off the paddle if the ball's bottom edge overlaps it.
      final ballBottom = _ballY + _ballSize;
      final ballCenterX = _ballX + _ballSize / 2;
      final hitsPaddleX = ballCenterX >= _paddleLeft &&
          ballCenterX <= _paddleLeft + _paddlewidth;
      final hitsPaddleY =
          ballBottom >= _paddleTop && ballBottom <= _paddleTop + _paddleheight;

      if (_ballSpeedY > 0 && hitsPaddleX && hitsPaddleY) {
        _ballY = _paddleTop - _ballSize;
        _ballSpeedY = -_ballSpeedY;
      } else if (_ballY >= _screenSize.height - _ballSize) {
        // Remove a life if the ball hits the bottom.
        widget.gameState.removeLife();
        // End the game if there are no more lives.
        if (widget.gameState.lives == 0) {
         _gameTimer?.cancel();
         _isPlaying = false;
         widget.gameState.saveScore();

         Navigator.pushNamed(context, '/end');
         return;        
        } else {
          // Reset to the start of the game_screen, but with 1 fewer life.
          _gameTimer?.cancel();
          _isPlaying = false;
          _resetGame();
        }
      }

      // Block collision added
      final ballRect = Rect.fromLTWH(_ballX, _ballY, _ballSize, _ballSize);

      const columns = 5;
      const gap = 6.0;
      const topOffset = 50.0;
      const blockHeight = 18.0;
      final blockWidth = (_screenSize.width - (columns + 1) * gap) / columns;

      for(final block in _blocks){
        if(block.broken) continue;

        final blockTop = topOffset + block.row * (blockHeight + gap);
        final blockLeft = gap + block.column * (blockWidth + gap);

        final blockRect = Rect.fromLTWH(blockLeft, blockTop, blockWidth, blockHeight);

        if (ballRect.overlaps(blockRect)) {
          block.broken = true;
          widget.gameState.addScore();
          _ballSpeedY = -_ballSpeedY;
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Game Screen')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                // Measures the play area so ball/paddle/block math knows the screen bounds.
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);

                  if (_screenSize != size) {
                    // Deferred since setState can't run during a build.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        if (_screenSize == Size.zero) {
                          // First measurement only — sets the ball's starting spot.
                          final paddleTop =
                              size.height - _paddleBottom - _paddleheight;
                          _ballX = size.width / 2 - _ballSize / 2;
                          _ballY = paddleTop - _ballSize - 4.0;
                        }
                        _screenSize = size;
                      });
                    });
                  }

                  return Stack(
                    children: [
                      // Blocks drawn first so the ball and paddle render on top.
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BlockPainting(blocks: _blocks),
                        ),
                      ),
                      Positioned(
                        left: _ballX,
                        top: _ballY,
                        child: Container(
                          width: _ballSize,
                          height: _ballSize,
                          decoration: const BoxDecoration(
                            color: _ballColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        left: _paddleLeft,
                        top: _paddleTop,
                        child: Container(
                          width: _paddlewidth,
                          height: _paddleheight,
                          decoration: BoxDecoration(
                            color: _paddleColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 20,
                        child: Text(
                          "Score: ${widget.gameState.score}",
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 24, fontWeight: 
                            FontWeight.bold,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Text(
                          "Lives: ${widget.gameState.lives}",
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 24, fontWeight: 
                            FontWeight.bold,
                          ),
                        ),
                      ),                      
                      if (!_isPlaying && widget.gameState.lives == _numLives)
                        const Center(
                          child: Text(
                            'Tap Start To Begin!',
                            style:
                                TextStyle(color: Colors.white, fontSize: 20.0),
                          ),
                        ), 
                      if (!_isPlaying && widget.gameState.lives < _numLives)
                        const Center(
                          child: Text(
                            'Tap Start To Keep Playing!',
                            style:
                                TextStyle(color: Colors.white, fontSize: 20.0),
                          ),
                        ),                                               
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _isPlaying ? null : _startGame,
                    child: const Text('Start'),
                  ),
                  const SizedBox(width: 16.0),
                  ElevatedButton(
                    // '/end' must be a registered route or this crashes on tap.
                    onPressed: () => Navigator.pushNamed(context, '/end'),
                    child: const Text('Finish Game'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// https://api.flutter.dev/flutter/dart-ui/Canvas-class.html
// https://api.flutter.dev/flutter/dart-ui/Canvas/drawRect.html

class BlockPainting extends CustomPainter {
  final List<Block> blocks;

  BlockPainting({
    required this.blocks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()..color = Colors.grey;

    // draw each block that isn't broken
    for (final block in blocks) {
      if (block.broken) continue;

      brush.color = block.color;

      final rect = blockRect(block, size);
      canvas.drawRect(rect, brush);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
