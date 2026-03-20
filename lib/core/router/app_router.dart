import 'package:go_router/go_router.dart';
import 'routes.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/room/screens/room_create_screen.dart';
import '../../features/room/screens/room_join_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/video_call/screens/video_call_screen.dart';
import '../../features/couple/screens/love_meter_screen.dart';
import '../../features/couple/screens/shared_notes_screen.dart';

final appRouter = GoRouter(
  initialLocation: Routes.home,
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: Routes.roomCreate,
      builder: (context, state) => const RoomCreateScreen(),
    ),
    GoRoute(
      path: Routes.roomJoin,
      builder: (context, state) => const RoomJoinScreen(),
    ),
    GoRoute(
      path: Routes.chat,
      builder: (context, state) => const ChatScreen(),
    ),
    GoRoute(
      path: Routes.videoCall,
      builder: (context, state) => const VideoCallScreen(),
    ),
    GoRoute(
      path: Routes.loveMeter,
      builder: (context, state) => const LoveMeterScreen(),
    ),
    GoRoute(
      path: Routes.sharedNotes,
      builder: (context, state) => const SharedNotesScreen(),
    ),
  ],
);
