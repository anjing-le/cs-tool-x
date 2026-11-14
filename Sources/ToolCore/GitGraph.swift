import Foundation

public struct GitGraphSegment: Sendable, Equatable {
  public enum Part: Sendable { case incoming, outgoing, through }
  public let from: Int
  public let to: Int
  public let color: Int
  public let part: Part
}
public struct GitGraphRow: Sendable {
  public let column: Int
  public let color: Int
  public let segments: [GitGraphSegment]
  public let overflow: Bool
}
/// Parent-linked lanes, independently keyed by repository. Page-boundary parents remain open continuations.
public enum GitGraph {
  public static let maxLanes = 64
  private struct Lane {
    let key: String
    var color: Int
  }
  public static func rows(_ commits: [GitCommit]) -> [GitGraphRow] {
    var lanes: [Lane] = []
    var output: [GitGraphRow] = []
    for commit in commits {
      let existed = lanes.contains { $0.key == commit.id }
      if !existed { lanes.append(Lane(key: commit.id, color: GitBrowser.colorIndex(commit.id))) }
      let before = lanes
      let column = lanes.firstIndex { $0.key == commit.id }!
      let color = lanes[column].color
      lanes.remove(at: column)
      var outgoing: [(String, Int)] = []
      for (index, parent) in commit.parents.enumerated() {
        let key = commit.repository + ":" + parent
        if !lanes.contains(where: { $0.key == key }) {
          let parentColor = index == 0 ? color : GitBrowser.colorIndex(key)
          lanes.insert(Lane(key: key, color: parentColor), at: min(column + index, lanes.count))
        }
        if let target = lanes.firstIndex(where: { $0.key == key }) {
          if index == 0 && column <= target { lanes[target].color = color }
          outgoing.append((key, lanes[target].color))
        }
      }
      var segments: [GitGraphSegment] = []
      if existed {
        segments.append(GitGraphSegment(from: column, to: column, color: color, part: .incoming))
      }
      for (i, lane) in before.enumerated() where lane.key != commit.id {
        if let j = lanes.firstIndex(where: { $0.key == lane.key }), i < maxLanes, j < maxLanes {
          segments.append(GitGraphSegment(from: i, to: j, color: lane.color, part: .through))
        }
      }
      for (key, laneColor) in outgoing {
        if let target = lanes.firstIndex(where: { $0.key == key }), column < maxLanes,
          target < maxLanes
        {
          segments.append(
            GitGraphSegment(from: column, to: target, color: laneColor, part: .outgoing))
        }
      }
      let overflow = max(before.count, lanes.count) > maxLanes
      if lanes.count > maxLanes { lanes = Array(lanes.prefix(maxLanes)) }
      output.append(
        GitGraphRow(column: column, color: color, segments: segments, overflow: overflow))
    }
    return output
  }
}
