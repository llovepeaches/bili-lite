import '../data/repository.dart';
import 'app_state.dart';
import 'auth_session.dart';
import 'library_state.dart';
import 'search_history.dart';

/// 应用级单例。项目规模很小，用顶层单例比层层透传 InheritedWidget 更直观；
/// 所有页面通过 AnimatedBuilder 订阅需要ChangeNotifier，避免全局 rebuild。
final BiliRepository repo = BiliRepository();
final AppState appState = AppState(repository: repo);
final LibraryState library = LibraryState();
final AuthSession authSession = AuthSession();
final SearchHistory searchHistory = SearchHistory();
