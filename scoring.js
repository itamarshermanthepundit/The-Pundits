window.PunditsScoring = {
  groupPickPoints: 5,
  awardPickPoints: 20,
  bracketWinnerPoints: 5,
  bracketExactScorePoints: 10,

  scoreGroupPredictions(predictions, officialGroups) {
    return predictions.reduce((total, prediction) => {
      const official = officialGroups[prediction.group_key] || [];
      const picked = prediction.ordered_teams || [];
      return total + picked.reduce((sum, team, index) => (
        sum + (official[index] === team ? this.groupPickPoints : 0)
      ), 0);
    }, 0);
  },

  scoreAwards(prediction, officialAwards) {
    if (!prediction || !officialAwards) return 0;
    return [
      ["champion", "champion"],
      ["top_scorer", "top_scorer"],
      ["top_assister", "top_assister"]
    ].reduce((total, [pickKey, resultKey]) => (
      total + (prediction[pickKey] && prediction[pickKey] === officialAwards[resultKey] ? this.awardPickPoints : 0)
    ), 0);
  },

  scoreBracket(predictions, officialMatches) {
    return predictions.reduce((total, prediction) => {
      const official = officialMatches[prediction.match_key];
      if (!official) return total;

      const winnerPoints = prediction.picked_winner === official.winner ? this.bracketWinnerPoints : 0;
      const exactScorePoints = (
        Number(prediction.predicted_home_score) === Number(official.home_score) &&
        Number(prediction.predicted_away_score) === Number(official.away_score)
      ) ? this.bracketExactScorePoints : 0;

      return total + winnerPoints + exactScorePoints;
    }, 0);
  }
};
