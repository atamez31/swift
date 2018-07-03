import Core
import Foundation
import SwiftSyntax

/// At least one blank line between each member of a type.
///
/// Optionally, declarations of single-line properties can be ignored.
///
/// Lint: If more than the maximum number of blank lines appear, a lint error is raised.
///       If there are no blank lines between members, a lint error is raised.
///
/// Format: Declarations with no blank lines will have a blank line inserted.
///         Declarations with more than the maximum number of blank lines will be reduced to the
///         maximum number of blank lines.
///
/// Configuration: maximumBlankLines, blankLineBetweenMembers.ignoreSingleLineProperties
///
/// - SeeAlso: https://google.github.io/swift#vertical-whitespace
public final class BlankLineBetweenMembers: SyntaxFormatRule {
  public override func visit(_ node: MemberDeclBlockSyntax) -> Syntax {
    var membersList = [MemberDeclListItemSyntax]()
    var hasValidNumOfBlankLines = true
    
    // Iterates through all the declaration of the member, to ensure that the declarations have
    // at least on blank line and doesn't exceed the maximum number of blank lines.
    for member in node.members {
      let currentMember = checkForNestedMembers(member)
      guard let memberTrivia = currentMember.leadingTrivia else { continue }
      let triviaWithoutTrailingSpaces = memberTrivia.withoutTrailingSpaces()
      guard let firstPiece = triviaWithoutTrailingSpaces.first else { continue }
      
      if exceedsMaxBlankLines(triviaWithoutTrailingSpaces) {
        let correctTrivia = removeExtraBlankLines(triviaWithoutTrailingSpaces, currentMember)
        let newMember = replaceTrivia(on: currentMember, token: currentMember.firstToken!,
                                      leadingTrivia: correctTrivia) as! MemberDeclListItemSyntax
        hasValidNumOfBlankLines = false
        membersList.append(newMember)
      }
      // Ensures that there is at least one blank line between each member of a type.
      // Unless is a single-line declaration and the format is configured to
      // ignored them.
      else if case .newlines(let numNewLines) = firstPiece,
              !ignoreItem(item: currentMember),
              numNewLines - 1 == 0 {
        let numBlankLines = member != node.members.first ? 1 : 0
        let correctTrivia = Trivia.newlines(numBlankLines) + memberTrivia
        let newMember = replaceTrivia(on: currentMember, token: currentMember.firstToken!,
                                      leadingTrivia: correctTrivia) as! MemberDeclListItemSyntax
        
        diagnose(.addBlankLine, on: currentMember)
        hasValidNumOfBlankLines = false
        membersList.append(newMember)
      }
      else {
        membersList.append(member)
      }
    }
    
    return hasValidNumOfBlankLines ? node :
           node.withMembers(SyntaxFactory.makeMemberDeclList(membersList))
  }
  
  /// Indicates if the given trivia has more than
  /// the maximum number of blank lines.
  func exceedsMaxBlankLines(_ trivia: Trivia) -> Bool {
    let maxBlankLines = context.configuration.maximumBlankLines

    for piece in trivia {
      if case .newlines(let num) = piece,
        num - 1 > maxBlankLines {
        return true
      }
    }
    return false
  }
  
  /// Returns the given trivia without any set of consecutive blank lines
  /// that exceeds the maximumBlankLines.
  func removeExtraBlankLines(_ trivia: Trivia, _ member: MemberDeclListItemSyntax) -> Trivia {
    let maxBlankLines = context.configuration.maximumBlankLines
    var pieces = [TriviaPiece]()
    
    // Iterates through the trivia, verifying that the number of blank
    // lines in the file do not exceed the maximumBlankLines. If it does
    // a lint error is raised.
    for piece in trivia {
      if case .newlines(let num) = piece,
         num - 1 > maxBlankLines {
        pieces.append(.newlines(maxBlankLines + 1))
        diagnose(.removeBlankLines(count: num - maxBlankLines)
                 ,on: member)
      }
      else {
        pieces.append(piece)
      }
    }
    return Trivia.init(pieces: pieces)
  }
  
  /// Indicates if a declaration has to be ignored by checking if it's
  /// a single line and if the format is configured to ignore single lines.
  func ignoreItem(item: MemberDeclListItemSyntax) -> Bool {
    guard let firstToken = item.firstToken else { return false }
    guard let lastToken = item.lastToken else { return false }
    
    let isSingleLine = firstToken.positionAfterSkippingLeadingTrivia.line ==
                       lastToken.positionAfterSkippingLeadingTrivia.line
    
    let ignoreLine = context.configuration.blankLineBetweenMembers
                     .ignoreSingleLineProperties
    
    return isSingleLine && ignoreLine
  }
  
  /// Recursively ensures all nested member types follows the BlankLineBetweenMembers rule.
  func checkForNestedMembers(_ member: MemberDeclListItemSyntax) -> MemberDeclListItemSyntax {
    if let nestedEnum = member.decl as? EnumDeclSyntax {
      let nestedMembers = visit(nestedEnum.members)
      let newDecl = nestedEnum.withMembers(nestedMembers as? MemberDeclBlockSyntax)

      return member.withDecl(newDecl)
    }
    else if let nestedStruct = member.decl as? StructDeclSyntax {
      let nestedMembers = visit(nestedStruct.members)
      let newDecl = nestedStruct.withMembers(nestedMembers as? MemberDeclBlockSyntax)

      return member.withDecl(newDecl)
    }
    else if let nestedClass = member.decl as? ClassDeclSyntax {
      let nestedMembers = visit(nestedClass.members)
      let newDecl = nestedClass.withMembers(nestedMembers as? MemberDeclBlockSyntax)
      
      return member.withDecl(newDecl)
    }
    else if let nestedExtension = member.decl as? ExtensionDeclSyntax {
      let nestedMembers = visit(nestedExtension.members)
      let newDecl = nestedExtension.withMembers(nestedMembers as? MemberDeclBlockSyntax)
      
      return member.withDecl(newDecl)
    }
    
    return member
  }
}

/// Indicates if the given trivia piece is any type of comment.
func isComment(_ triviaPiece: TriviaPiece) -> Bool {
  switch triviaPiece {
  case .lineComment(_), .docLineComment(_),
       .blockComment(_), .docBlockComment(_):
    return true
  default:
    return false
  }
}

extension Diagnostic.Message {
  static let addBlankLine = Diagnostic.Message(.warning, "add one blank line between declarations")
  
  static func removeBlankLines(count: Int) -> Diagnostic.Message {
    let ending = count > 1 ? "s" : ""
    return Diagnostic.Message(.warning, "remove \(count) blank line\(ending)")
  }
}
