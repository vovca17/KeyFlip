import Foundation

public enum Names {
    // A small editable-in-code starter vocabulary; all checks ignore case.
    public static let builtIn: Set<String> = Set("""
    александр александра алексей алина алиса алла анастасия анатолий андрей анна антон артем артём артур
    борис вадим валентин валентина валерий валерия василий вера виктор виктория вика виталий владимир владислав
    галина георгий григорий даниил данил дарья даша денис дмитрий дима евгений евгения егор екатерина елена
    елизавета жанна иван игорь илья инна ирина катя кирилл ксения лариса лев лена леонид лилия любовь людмила
    максим макс маргарита марина мария маша матвей михаил миша надежда наталья никита николай нина олег ольга
    павел петр пётр полина роман руслан светлана семен семён сергей софия софья станислав степан татьяна тимофей
    федор фёдор юлия юрий яна ярослав
    alex alexander alexandra aleksandr aleksandra alexey alexei aleksey alina alice alisa alla anastasia anatoly
    andrey andrei anna anne anton artem artyom arthur artur boris vadim valentin valentina valery valeria
    vasily vera victor viktor victoria viktoria vika vitaly vladimir vladislav galina george georgy grigory
    daniel daniil danil daria darya dasha denis dmitry dmitriy dima evgeny evgeniya egor ekaterina elena
    elizaveta zhanna ivan igor ilya inna irina katya kirill ksenia larisa lev lena leonid lilia lily lyubov
    ludmila lyudmila maxim maksim max margarita marina maria masha matvey mikhail misha nadezhda natalia
    natalya nikita nikolay nina oleg olga pavel peter petr pyotr polina roman ruslan svetlana semen semyon
    sergey sergei sofia sophia sofya stanislav stepan tatiana tatyana timofey fedor fyodor julia yulia yuri
    yana yaroslav john jane james michael david robert william richard thomas charles daniel matthew emma
    olivia sophie sarah emily jessica jennifer mary elizabeth
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    public static func candidate(_ text: String, additional: Set<String> = []) -> String? {
        guard (2...40).contains(text.count), text.allSatisfy(\.isLetter) else { return nil }
        let accepted = builtIn.union(additional.map { $0.lowercased() })
        guard !accepted.contains(text.lowercased()) else { return nil }
        let converted = Layout.convert(text)
        guard converted != text, accepted.contains(converted.lowercased()) else { return nil }
        return converted
    }
}
