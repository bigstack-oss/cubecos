import { Progress } from 'antd';
import AntProgress from './styles/progress.style';
import WithDirection from '../../config/withDirection';

const WDProgress = AntProgress(Progress);
const isoProgress = WithDirection(WDProgress);

export default isoProgress;
