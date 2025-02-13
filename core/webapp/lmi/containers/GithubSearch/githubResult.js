import React from 'react';
import Loader from '../../components/utility/loader';
import HelperText from '../../components/utility/helper-text';
import Pagination from '../../components/uielements/pagination';
import { per_page } from '../../redux/githubSearch/sagas';
import {
  GithubResultListStyleWrapper,
  GithubResultStyleWrapper
} from './githubResult.style';

function SearchList(result) {
  return (
    <GithubResultListStyleWrapper className="isoGithubResultList">
      {result.map(item => {
        const onClick = () => {
          window.open(item.html_url, '_blank');
        };
        const updateDate = new Date(item.updated_at).toDateString();
        return (
          <div key={item.id} className="isoSingleRepository">
            <div className="titleAndLanguage">
              <h3>
                <a href="#" onClick={onClick}>
                  {`${item.full_name} `}
                </a>
              </h3>

              {item.language ? (
                <span className="language">{item.language}</span>
              ) : (
                ''
              )}
              {item.stargazers_count ? (
                <span className="totalStars">{item.stargazers_count}</span>
              ) : (
                ''
              )}
            </div>
            {item.description ? <p>{item.description}</p> : ''}
            <span className="updateDate">Updated on {updateDate}</span>
          </div>
        );
      })}
    </GithubResultListStyleWrapper>
  );
}
export default ({ GitSearch, onPageChange }) => {
  const { searcText, result, loading, error, page, total_count } = GitSearch;
  if (!searcText) {
    return <div />;
  }
  if (loading) {
    return <Loader />;
  }
  if (error || !total_count) {
    return <HelperText text="THERE ARE SOME ERRORS" />;
  }
  if (result.length === 0) {
    return <HelperText text="No Result Found" />;
  }
  const visibleItem = total_count > 1000 ? 1000 : total_count;
  const pageCount = Math.floor(visibleItem / per_page);
  return (
    <GithubResultStyleWrapper className="isoGithubSearchResult">
      <p className="isoTotalRepository">
        <span>{`${total_count}`} repository results</span>
      </p>
      {SearchList(result)}
      <div className="githubSearchPagination">
        <Pagination
          defaultCurrent={page}
          total={pageCount}
          onChange={page => {
            onPageChange(searcText, page);
          }}
        />
      </div>
    </GithubResultStyleWrapper>
  );
};
