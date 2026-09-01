import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'heart_rate_state.dart';

class HeartRateCubit extends Cubit<HeartRateState> {
  HeartRateCubit() : super(HeartRateInitial());
}
