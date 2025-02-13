import { all, takeEvery, put, call } from 'redux-saga/effects';
import actions from './actions';
import { youtubeSearchApi } from '../../config';
export const per_page = 10;
const maxResults = 10;
const gitSearchApi = `https://www.googleapis.com/youtube/v3/search?maxResults=${maxResults}&type=video&key=${youtubeSearchApi}&part=snippet`;

const onSearchReqeust = async (searcText, pageToken) =>
  await fetch(`${gitSearchApi}&q=${encodeURIComponent(searcText)}${pageToken}`)
    .then(res => res.json())
    .then(res => res)
    .catch(error => error);

function* searchRequest({ payload }) {
  const { searcText, pageToken } = payload;
  try {
    const searchResult = yield call(
      onSearchReqeust,
      searcText,
      pageToken ? `&pageToken=${pageToken}` : ''
    );
    if (searchResult.items) {
      yield put(
        actions.gitSearchSuccess(
          searchResult.items,
          searchResult.pageInfo.totalResults,
          searchResult.nextPageToken,
          searchResult.prevPageToken
        )
      );
    } else {
      yield put(actions.gitSearchSuccess());
    }
  } catch (error) {
    yield put(actions.gitSearchSuccess());
  }
}
export default function* rootSaga() {
  yield all([takeEvery(actions.YOUTUBE_SEARCH, searchRequest)]);
}
